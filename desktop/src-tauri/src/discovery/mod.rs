use std::{
    process,
    sync::Mutex,
    time::{SystemTime, UNIX_EPOCH},
};

use mdns_sd::{ServiceDaemon, ServiceInfo};
use tauri::{AppHandle, Manager};

pub const EGGCLIP_MDNS_SERVICE_TYPE: &str = "_eggclip._tcp.local.";

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
}
