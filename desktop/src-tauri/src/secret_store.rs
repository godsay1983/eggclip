use std::fmt;

#[cfg(windows)]
use windows_sys::Win32::{
    Foundation::{GetLastError, ERROR_NOT_FOUND},
    Security::Credentials::{
        CredFree, CredReadW, CredWriteW, CREDENTIALW, CRED_PERSIST_LOCAL_MACHINE, CRED_TYPE_GENERIC,
    },
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SecretStoreError {
    Unavailable(String),
    ReadFailed(u32),
    WriteFailed(u32),
    InvalidLength { actual: usize, expected: usize },
}

impl fmt::Display for SecretStoreError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SecretStoreError::Unavailable(message) => formatter.write_str(message),
            SecretStoreError::ReadFailed(code) => {
                write!(formatter, "Windows Credential Manager read failed: {code}")
            }
            SecretStoreError::WriteFailed(code) => {
                write!(formatter, "Windows Credential Manager write failed: {code}")
            }
            SecretStoreError::InvalidLength { actual, expected } => {
                write!(
                    formatter,
                    "stored secret has invalid length: {actual}, expected {expected}"
                )
            }
        }
    }
}

impl std::error::Error for SecretStoreError {}

pub trait SecretBytesStore {
    fn load_secret(&self, secret_ref: &str) -> Result<Option<Vec<u8>>, SecretStoreError>;

    fn save_secret(&mut self, secret_ref: &str, secret: &[u8]) -> Result<(), SecretStoreError>;
}

#[cfg(windows)]
pub struct WindowsCredentialSecretStore;

#[cfg(windows)]
impl SecretBytesStore for WindowsCredentialSecretStore {
    fn load_secret(&self, secret_ref: &str) -> Result<Option<Vec<u8>>, SecretStoreError> {
        let target_name = wide_null(secret_ref);
        let mut credential: *mut CREDENTIALW = std::ptr::null_mut();
        let read_ok =
            unsafe { CredReadW(target_name.as_ptr(), CRED_TYPE_GENERIC, 0, &mut credential) };

        if read_ok == 0 {
            let error = unsafe { GetLastError() };
            if error == ERROR_NOT_FOUND {
                return Ok(None);
            }
            return Err(SecretStoreError::ReadFailed(error));
        }

        let credential = CredentialHandle(credential);
        let credential_ref = unsafe { &*credential.0 };
        if credential_ref.CredentialBlob.is_null() {
            return Ok(None);
        }

        let source = unsafe {
            std::slice::from_raw_parts(
                credential_ref.CredentialBlob,
                credential_ref.CredentialBlobSize as usize,
            )
        };
        Ok(Some(source.to_vec()))
    }

    fn save_secret(&mut self, secret_ref: &str, secret: &[u8]) -> Result<(), SecretStoreError> {
        let mut target_name = wide_null(secret_ref);
        let mut user_name = wide_null("EggClip");
        let mut credential_blob = secret.to_vec();
        let credential = CREDENTIALW {
            Type: CRED_TYPE_GENERIC,
            TargetName: target_name.as_mut_ptr(),
            CredentialBlobSize: credential_blob.len() as u32,
            CredentialBlob: credential_blob.as_mut_ptr(),
            Persist: CRED_PERSIST_LOCAL_MACHINE,
            UserName: user_name.as_mut_ptr(),
            ..Default::default()
        };

        let write_ok = unsafe { CredWriteW(&credential, 0) };
        credential_blob.fill(0);
        if write_ok == 0 {
            let error = unsafe { GetLastError() };
            return Err(SecretStoreError::WriteFailed(error));
        }

        Ok(())
    }
}

pub struct UnavailableSecretStore;

impl SecretBytesStore for UnavailableSecretStore {
    fn load_secret(&self, _secret_ref: &str) -> Result<Option<Vec<u8>>, SecretStoreError> {
        Err(SecretStoreError::Unavailable(
            "system credential store is unavailable on this platform".to_string(),
        ))
    }

    fn save_secret(&mut self, _secret_ref: &str, _secret: &[u8]) -> Result<(), SecretStoreError> {
        Err(SecretStoreError::Unavailable(
            "system credential store is unavailable on this platform".to_string(),
        ))
    }
}

#[cfg(windows)]
struct CredentialHandle(*mut CREDENTIALW);

#[cfg(windows)]
impl Drop for CredentialHandle {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe { CredFree(self.0.cast()) };
        }
    }
}

#[cfg(windows)]
fn wide_null(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(std::iter::once(0)).collect()
}
