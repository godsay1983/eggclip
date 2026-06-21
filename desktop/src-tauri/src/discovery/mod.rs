use std::{
    process,
    sync::Mutex,
    time::{SystemTime, UNIX_EPOCH},
};

use if_addrs::IfAddr;
use mdns_sd::{ServiceDaemon, ServiceInfo};
use serde::Serialize;
use tauri::{AppHandle, Manager};

pub const EGGCLIP_MDNS_SERVICE_TYPE: &str = "_eggclip._tcp.local.";

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PocNetworkAddress {
    interface_name: String,
    address: String,
    is_tunnel: bool,
}

#[derive(Default)]
pub struct PocDiscoveryRuntime {
    registration: Mutex<Option<PocMdnsRegistration>>,
}

struct PocMdnsRegistration {
    daemon: ServiceDaemon,
    fullname: String,
}

pub fn publish_poc_service(app: &AppHandle, port: u16) -> Result<(), String> {
    let runtime = app.state::<PocDiscoveryRuntime>();
    let mut registration = runtime
        .registration
        .lock()
        .map_err(|_| "mDNS POC 状态锁已损坏".to_owned())?;
    if registration.is_some() {
        return Ok(());
    }

    let instance_id = temporary_instance_id()?;
    let daemon = ServiceDaemon::new().map_err(|error| format!("无法创建 mDNS 服务：{error}"))?;
    let service = build_poc_service_info(port, &instance_id)?;
    let fullname = service.get_fullname().to_owned();
    daemon
        .register(service)
        .map_err(|error| format!("无法发布 mDNS POC 服务：{error}"))?;
    *registration = Some(PocMdnsRegistration { daemon, fullname });
    Ok(())
}

pub fn unpublish_poc_service(app: &AppHandle) {
    let runtime = app.state::<PocDiscoveryRuntime>();
    let registration = runtime
        .registration
        .lock()
        .ok()
        .and_then(|mut current| current.take());
    if let Some(registration) = registration {
        let _ = registration.daemon.unregister(&registration.fullname);
        let _ = registration.daemon.shutdown();
    }
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

fn build_poc_service_info(port: u16, instance_id: &str) -> Result<ServiceInfo, String> {
    let hostname = format!("{instance_id}.local.");
    let properties = [
        ("protocolVersion", "0"),
        ("instanceId", instance_id),
        ("capabilities", "text-poc"),
    ];
    ServiceInfo::new(
        EGGCLIP_MDNS_SERVICE_TYPE,
        instance_id,
        &hostname,
        "",
        port,
        &properties[..],
    )
    .map(ServiceInfo::enable_addr_auto)
    .map_err(|error| format!("无法构建 mDNS POC 服务信息：{error}"))
}

fn temporary_instance_id() -> Result<String, String> {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| "系统时间早于 Unix epoch，无法生成临时 mDNS 实例 ID".to_owned())?
        .as_millis();
    Ok(format!("eggclip-poc-{:x}-{millis:x}", process::id()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn poc_service_only_exposes_allowed_txt_properties() {
        let service = build_poc_service_info(31415, "eggclip-poc-test")
            .expect("valid POC service information");

        assert_eq!(service.get_port(), 31415);
        assert_eq!(service.get_property_val_str("protocolVersion"), Some("0"));
        assert_eq!(
            service.get_property_val_str("instanceId"),
            Some("eggclip-poc-test")
        );
        assert_eq!(
            service.get_property_val_str("capabilities"),
            Some("text-poc")
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
