use std::{
    collections::{hash_map::DefaultHasher, HashMap},
    hash::{Hash, Hasher},
    sync::atomic::Ordering,
    time::Duration,
};

use tauri::{AppHandle, Manager};
use tokio::time::{interval, Instant, MissedTickBehavior};
use uuid::Uuid;

use super::{
    authenticated_device_peers, outbound::connect_saved_trusted_peer, PocTransportRuntime,
};
use crate::{
    discovery::{discovered_services, local_ipv4_candidates, MdnsServiceCandidate},
    settings::database_path,
    storage::{
        open_database,
        repositories::{DeviceRecord, DeviceRepository},
    },
};

const RECONNECT_TICK: Duration = Duration::from_secs(2);
const RECONNECT_BASE_DELAY: Duration = Duration::from_secs(1);
const RECONNECT_MAX_DELAY: Duration = Duration::from_secs(60);
const WAKE_GAP: Duration = Duration::from_secs(8);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct RouteKey {
    space_id: Uuid,
    device_id: Uuid,
}

struct RetryState {
    failures: u32,
    retry_at: Instant,
}

impl RetryState {
    fn ready(now: Instant) -> Self {
        Self {
            failures: 0,
            retry_at: now,
        }
    }

    fn fail(&mut self, key: RouteKey, now: Instant) {
        self.failures = self.failures.saturating_add(1);
        self.retry_at = now + reconnect_delay(key, self.failures);
    }
}

pub(crate) fn start_trusted_reconnect_task(app: AppHandle) {
    let runtime = app.state::<PocTransportRuntime>();
    if runtime.reconnect_task_started.swap(true, Ordering::AcqRel) {
        return;
    }
    tauri::async_runtime::spawn(async move {
        let mut ticker = interval(RECONNECT_TICK);
        ticker.set_missed_tick_behavior(MissedTickBehavior::Delay);
        let mut retries = HashMap::<RouteKey, RetryState>::new();
        let mut previous_network_fingerprint = String::new();
        let mut previous_tick = Instant::now();
        loop {
            ticker.tick().await;
            let now = Instant::now();
            if !transport_is_running(&app) {
                retries.clear();
                previous_tick = now;
                continue;
            }

            let candidates = discovered_services(&app);
            let network_fingerprint = network_fingerprint(&candidates);
            let resumed_or_changed = now.duration_since(previous_tick) > WAKE_GAP
                || network_fingerprint != previous_network_fingerprint;
            previous_tick = now;
            if resumed_or_changed {
                for state in retries.values_mut() {
                    state.retry_at = now;
                }
            }
            previous_network_fingerprint = network_fingerprint;

            let routes = match load_dial_coordinators(&app) {
                Ok(routes) => routes,
                Err(_) => continue,
            };
            let active = authenticated_device_peers(&app);
            let valid_keys = routes
                .iter()
                .map(route_key)
                .collect::<std::collections::HashSet<_>>();
            retries.retain(|key, _| valid_keys.contains(key));
            for route in routes {
                let key = route_key(&route);
                if active.contains_key(&(key.space_id, key.device_id)) {
                    retries.remove(&key);
                    continue;
                }
                let state = retries.entry(key).or_insert_with(|| RetryState::ready(now));
                if now < state.retry_at {
                    continue;
                }
                let endpoints = reconnect_endpoints(&route, &candidates);
                if endpoints.is_empty() {
                    state.fail(key, now);
                    continue;
                }
                match connect_saved_trusted_peer(
                    app.clone(),
                    key.space_id,
                    key.device_id,
                    endpoints,
                )
                .await
                {
                    Ok(_) => {
                        retries.remove(&key);
                    }
                    Err(_)
                        if authenticated_device_peers(&app)
                            .contains_key(&(key.space_id, key.device_id)) =>
                    {
                        retries.remove(&key);
                    }
                    Err(_) => state.fail(key, Instant::now()),
                }
            }
        }
    });
}

fn transport_is_running(app: &AppHandle) -> bool {
    app.state::<PocTransportRuntime>()
        .server
        .lock()
        .map(|server| server.is_some())
        .unwrap_or(false)
}

fn load_dial_coordinators(app: &AppHandle) -> Result<Vec<DeviceRecord>, ()> {
    let path = database_path(app).map_err(|_| ())?;
    let connection = open_database(path).map_err(|_| ())?;
    DeviceRepository::new(&connection)
        .list_dial_coordinators()
        .map_err(|_| ())
}

fn route_key(route: &DeviceRecord) -> RouteKey {
    RouteKey {
        space_id: route.device.space_id,
        device_id: route.device.device_id,
    }
}

fn reconnect_endpoints(
    route: &DeviceRecord,
    candidates: &[MdnsServiceCandidate],
) -> Vec<(String, u16)> {
    let mut endpoints = candidates
        .iter()
        .filter(|candidate| candidate.device_id == route.device.device_id.to_string())
        .flat_map(|candidate| {
            candidate
                .addresses
                .iter()
                .cloned()
                .map(move |address| (address, candidate.port))
        })
        .collect::<Vec<_>>();
    endpoints.sort();
    endpoints.dedup();
    if let (Some(host), Some(port)) = (
        route.route.last_successful_host.as_ref(),
        route.route.last_successful_port,
    ) {
        let fallback = (host.clone(), port);
        if !endpoints.contains(&fallback) {
            endpoints.push(fallback);
        }
    }
    endpoints
}

fn reconnect_delay(key: RouteKey, failures: u32) -> Duration {
    let exponent = failures.saturating_sub(1).min(6);
    let base_ms = RECONNECT_BASE_DELAY
        .as_millis()
        .saturating_mul(1u128 << exponent)
        .min(RECONNECT_MAX_DELAY.as_millis());
    let mut hasher = DefaultHasher::new();
    key.hash(&mut hasher);
    failures.hash(&mut hasher);
    let jitter_percent = 80 + (hasher.finish() % 41) as u128;
    Duration::from_millis(
        base_ms
            .saturating_mul(jitter_percent)
            .saturating_div(100)
            .min(RECONNECT_MAX_DELAY.as_millis()) as u64,
    )
}

fn network_fingerprint(candidates: &[MdnsServiceCandidate]) -> String {
    let mut values = local_ipv4_candidates()
        .unwrap_or_default()
        .into_iter()
        .map(|address| format!("local:{}", address.address))
        .collect::<Vec<_>>();
    values.extend(candidates.iter().flat_map(|candidate| {
        candidate
            .addresses
            .iter()
            .map(move |address| format!("{}:{address}:{}", candidate.device_id, candidate.port))
    }));
    values.sort();
    values.join("|")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        storage::repositories::TrustedDeviceRoute,
        sync::{Device, DeviceConnectionState, DeviceTrustState, TrustedRouteRole},
    };

    fn route(device_id: Uuid) -> DeviceRecord {
        DeviceRecord {
            device: Device {
                device_id,
                space_id: Uuid::now_v7(),
                display_name: "协调端".to_string(),
                identity_public_key_ref: "identity".to_string(),
                trust_state: DeviceTrustState::Trusted,
                connection_state: DeviceConnectionState::Offline,
                last_seen_at: None,
            },
            route: TrustedDeviceRoute {
                role: TrustedRouteRole::DialCoordinator,
                last_successful_host: Some("192.168.1.8".to_string()),
                last_successful_port: Some(41234),
            },
            paired_at: Some(1),
            revoked_at: None,
        }
    }

    #[test]
    fn current_mdns_candidate_precedes_saved_fallback_and_matches_exact_device() {
        let device_id = Uuid::now_v7();
        let other_id = Uuid::now_v7();
        let candidates = vec![
            MdnsServiceCandidate {
                instance_id: other_id.to_string(),
                device_id: other_id.to_string(),
                addresses: vec!["10.0.0.99".to_string()],
                port: 3000,
                protocol_version: 1,
                capabilities: vec!["sync-v1".to_string()],
            },
            MdnsServiceCandidate {
                instance_id: device_id.to_string(),
                device_id: device_id.to_string(),
                addresses: vec!["10.0.0.8".to_string()],
                port: 31415,
                protocol_version: 1,
                capabilities: vec!["sync-v1".to_string()],
            },
        ];
        assert_eq!(
            reconnect_endpoints(&route(device_id), &candidates),
            vec![
                ("10.0.0.8".to_string(), 31415),
                ("192.168.1.8".to_string(), 41234),
            ]
        );
    }

    #[test]
    fn exponential_backoff_is_jittered_and_bounded() {
        let key = RouteKey {
            space_id: Uuid::now_v7(),
            device_id: Uuid::now_v7(),
        };
        let first = reconnect_delay(key, 1);
        let later = reconnect_delay(key, 5);
        let capped = reconnect_delay(key, 100);
        assert!((Duration::from_millis(800)..=Duration::from_millis(1_200)).contains(&first));
        assert!(later > first);
        assert!(capped <= RECONNECT_MAX_DELAY);
    }
}
