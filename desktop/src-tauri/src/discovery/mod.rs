use std::{
    collections::BTreeSet,
    sync::{Arc, Mutex},
};

use if_addrs::IfAddr;
use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use serde::Serialize;
use tauri::{AppHandle, Manager};

pub const EGGCLIP_MDNS_SERVICE_TYPE: &str = "_eggclip._tcp.local.";
const EGGCLIP_PROTOCOL_VERSION: u16 = 1;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PocNetworkAddress {
    pub(crate) interface_name: String,
    pub(crate) address: String,
    pub(crate) is_tunnel: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MdnsServiceCandidate {
    pub(crate) instance_id: String,
    pub(crate) device_id: String,
    pub(crate) addresses: Vec<String>,
    pub(crate) port: u16,
    pub(crate) protocol_version: u16,
    pub(crate) capabilities: Vec<String>,
}

#[derive(Default)]
pub struct PocDiscoveryRuntime {
    registration: Mutex<Option<MdnsRegistration>>,
    candidates: Arc<Mutex<Vec<MdnsServiceCandidate>>>,
}

struct MdnsRegistration {
    daemon: ServiceDaemon,
    fullname: String,
}

pub fn publish_service(app: &AppHandle, port: u16, local_device_id: &str) -> Result<(), String> {
    let runtime = app.state::<PocDiscoveryRuntime>();
    let mut registration = runtime
        .registration
        .lock()
        .map_err(|_| "mDNS 状态锁已损坏".to_owned())?;
    if registration.is_some() {
        return Ok(());
    }

    let daemon = ServiceDaemon::new().map_err(|error| format!("无法创建 mDNS 服务：{error}"))?;
    let service = build_service_info(port, local_device_id)?;
    let fullname = service.get_fullname().to_owned();
    daemon
        .register(service)
        .map_err(|error| format!("无法发布 mDNS 服务：{error}"))?;
    let receiver = daemon
        .browse(EGGCLIP_MDNS_SERVICE_TYPE)
        .map_err(|error| format!("无法浏览 mDNS 服务：{error}"))?;
    let candidates = Arc::clone(&runtime.candidates);
    let own_device_id = local_device_id.to_owned();
    std::thread::spawn(move || {
        while let Ok(event) = receiver.recv() {
            match event {
                ServiceEvent::ServiceResolved(service) => {
                    if let Some(candidate) = resolved_candidate(&service, &own_device_id) {
                        if let Ok(mut current) = candidates.lock() {
                            current.retain(|item| item.instance_id != candidate.instance_id);
                            current.push(candidate);
                            current.sort_by(|left, right| left.instance_id.cmp(&right.instance_id));
                            current.truncate(32);
                        }
                    }
                }
                ServiceEvent::ServiceRemoved(_, fullname) => {
                    if let Ok(mut current) = candidates.lock() {
                        current.retain(|item| {
                            !fullname.starts_with(&format!("eggclip-{}.", item.instance_id))
                        });
                    }
                }
                _ => {}
            }
        }
    });
    *registration = Some(MdnsRegistration { daemon, fullname });
    Ok(())
}

pub fn unpublish_service(app: &AppHandle) {
    let runtime = app.state::<PocDiscoveryRuntime>();
    let registration = runtime
        .registration
        .lock()
        .ok()
        .and_then(|mut current| current.take());
    if let Some(registration) = registration {
        let _ = registration.daemon.stop_browse(EGGCLIP_MDNS_SERVICE_TYPE);
        let _ = registration.daemon.unregister(&registration.fullname);
        let _ = registration.daemon.shutdown();
    }
    if let Ok(mut candidates) = runtime.candidates.lock() {
        candidates.clear();
    };
}

pub fn discovered_services(app: &AppHandle) -> Vec<MdnsServiceCandidate> {
    app.state::<PocDiscoveryRuntime>()
        .candidates
        .lock()
        .map(|items| items.clone())
        .unwrap_or_default()
}

pub fn local_ipv4_candidates() -> Result<Vec<PocNetworkAddress>, String> {
    let interfaces =
        if_addrs::get_if_addrs().map_err(|error| format!("无法枚举本机网络地址：{error}"))?;
    let mut candidates = interfaces
        .into_iter()
        .filter(|interface| interface.is_oper_up())
        .filter_map(|interface| {
            let is_tunnel = interface.is_p2p();
            match interface.addr {
                IfAddr::V4(address) if is_usable_lan_ipv4(address.ip) => Some(PocNetworkAddress {
                    interface_name: interface.name,
                    address: address.ip.to_string(),
                    is_tunnel,
                }),
                _ => None,
            }
        })
        .collect::<Vec<_>>();
    candidates.sort_by(|left, right| {
        left.is_tunnel
            .cmp(&right.is_tunnel)
            .then_with(|| left.interface_name.cmp(&right.interface_name))
            .then_with(|| left.address.cmp(&right.address))
    });
    candidates.dedup_by(|left, right| left.address == right.address);
    Ok(candidates)
}

fn is_usable_lan_ipv4(address: std::net::Ipv4Addr) -> bool {
    !address.is_loopback()
        && !address.is_link_local()
        && !address.is_unspecified()
        && !address.is_multicast()
        && !address.is_broadcast()
}

fn build_service_info(port: u16, device_id: &str) -> Result<ServiceInfo, String> {
    let instance_id = format!("eggclip-{device_id}");
    let hostname = format!("{instance_id}.local.");
    let properties = [
        ("protocolVersion", EGGCLIP_PROTOCOL_VERSION.to_string()),
        ("instanceId", device_id.to_owned()),
        ("deviceId", device_id.to_owned()),
        ("transport", "ws".to_owned()),
        ("capabilities", "text/plain,pairing-v1,sync-v1".to_owned()),
    ];
    ServiceInfo::new(
        EGGCLIP_MDNS_SERVICE_TYPE,
        &instance_id,
        &hostname,
        "",
        port,
        &properties[..],
    )
    .map(ServiceInfo::enable_addr_auto)
    .map_err(|error| format!("无法构建 mDNS 服务信息：{error}"))
}

fn resolved_candidate(
    service: &mdns_sd::ResolvedService,
    own_device_id: &str,
) -> Option<MdnsServiceCandidate> {
    let protocol_version = service
        .get_property_val_str("protocolVersion")?
        .parse::<u16>()
        .ok()?;
    if protocol_version != EGGCLIP_PROTOCOL_VERSION || service.get_port() == 0 {
        return None;
    }
    let device_id = service.get_property_val_str("deviceId")?.trim();
    let instance_id = service.get_property_val_str("instanceId")?.trim();
    if !is_uuid(device_id) || instance_id != device_id || device_id == own_device_id {
        return None;
    }
    let addresses = service
        .get_addresses_v4()
        .into_iter()
        .filter(|address| is_usable_lan_ipv4(*address))
        .map(|address| address.to_string())
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    if addresses.is_empty() {
        return None;
    }
    let capabilities = service
        .get_property_val_str("capabilities")
        .unwrap_or_default()
        .split(',')
        .filter(|value| !value.is_empty())
        .take(8)
        .map(str::to_owned)
        .collect();
    Some(MdnsServiceCandidate {
        instance_id: instance_id.to_owned(),
        device_id: device_id.to_owned(),
        addresses,
        port: service.get_port(),
        protocol_version,
        capabilities,
    })
}

fn is_uuid(value: &str) -> bool {
    uuid::Uuid::parse_str(value).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formal_service_exposes_only_discovery_and_capability_metadata() {
        let device_id = "018ff6f0-4adf-7d31-a987-3ef2b25d0212";
        let service = build_service_info(31415, device_id).expect("valid service information");
        assert_eq!(service.get_port(), 31415);
        assert_eq!(service.get_property_val_str("protocolVersion"), Some("1"));
        assert_eq!(service.get_property_val_str("instanceId"), Some(device_id));
        assert_eq!(service.get_property_val_str("deviceId"), Some(device_id));
        assert_eq!(service.get_property_val_str("transport"), Some("ws"));
        assert_eq!(
            service.get_property_val_str("capabilities"),
            Some("text/plain,pairing-v1,sync-v1")
        );
        assert_eq!(service.get_property_val_str("deviceName"), None);
    }

    #[test]
    fn filters_unusable_ipv4_addresses_from_diagnostics() {
        use std::net::Ipv4Addr;
        assert!(!is_usable_lan_ipv4(Ipv4Addr::LOCALHOST));
        assert!(!is_usable_lan_ipv4(Ipv4Addr::new(169, 254, 1, 2)));
        assert!(!is_usable_lan_ipv4(Ipv4Addr::UNSPECIFIED));
        assert!(is_usable_lan_ipv4(Ipv4Addr::new(192, 168, 3, 124)));
        assert!(is_usable_lan_ipv4(Ipv4Addr::new(172, 18, 0, 1)));
    }
}
