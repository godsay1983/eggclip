export enum UiMessageCode {
  UNKNOWN = 'ui_message_unknown',
  PAIRING_INITIAL = 'ui_pairing_initial',
  PAIRING_INPUT_UPDATED = 'ui_pairing_input_updated',
  PAIRING_PASTE_IMPORTED = 'ui_pairing_paste_imported',
  PAIRING_VALID_REQUIRED = 'ui_pairing_valid_required',
  PAIRING_CODE_MATCHED = 'ui_pairing_code_matched',
  PAIRING_COMPLETED = 'ui_pairing_completed',
  PAIRING_INVITATION_VALID = 'ui_pairing_invitation_valid',
  PAIRING_INVITATION_INVALID = 'ui_pairing_invitation_invalid',
  HISTORY_LOAD_FAILED = 'ui_history_load_failed',
  HISTORY_DELETE_FAILED = 'ui_history_delete_failed',
  HISTORY_CLEAR_FAILED = 'ui_history_clear_failed',
  HISTORY_SAVE_FAILED = 'ui_history_save_failed',
  HISTORY_BROADCAST_ALLOWED = 'ui_history_broadcast_allowed',
  HISTORY_BROADCAST_PAUSED = 'ui_history_broadcast_paused',
  SETTINGS_READ_FAILED = 'ui_settings_read_failed',
  SETTINGS_INVALID = 'ui_settings_invalid',
  SETTINGS_SAVE_FAILED = 'ui_settings_save_failed',
  SETTINGS_CLEAR_HISTORY_FAILED = 'ui_settings_clear_history_failed',
  TRUSTED_NAME_EMPTY = 'ui_trusted_name_empty',
  TRUSTED_DEVICE_MISSING = 'ui_trusted_device_missing',
  TRUSTED_KEY_CLEANUP_FAILED = 'ui_trusted_key_cleanup_failed',
  CLIPBOARD_READ_FAILED = 'ui_clipboard_read_failed',
  CLIPBOARD_NOT_PLAIN_TEXT = 'ui_clipboard_not_plain_text',
  CLIPBOARD_EMPTY = 'ui_clipboard_empty',
  CLIPBOARD_TOO_LARGE = 'ui_clipboard_too_large',
  CLIPBOARD_READ_SUCCESS = 'ui_clipboard_read_success',
  CLIPBOARD_WRITE_SUCCESS = 'ui_clipboard_write_success',
  CLIPBOARD_WRITE_FAILED = 'ui_clipboard_write_failed',
  SCAN_EMPTY = 'ui_scan_empty',
  SCAN_SUCCESS = 'ui_scan_success',
  SCAN_FAILED = 'ui_scan_failed',
  CONNECTION_WAITING_TITLE = 'ui_connection_waiting_title',
  CONNECTION_WAITING_DESCRIPTION = 'ui_connection_waiting_description',
  CONNECTION_AUTHENTICATED_TITLE = 'ui_connection_authenticated_title',
  CONNECTION_AUTHENTICATED_DESCRIPTION = 'ui_connection_authenticated_description',
  CONNECTION_PREPARING_TITLE = 'ui_connection_preparing_title',
  CONNECTION_PREPARING_DESCRIPTION = 'ui_connection_preparing_description',
  CONNECTION_CONNECTING_TITLE = 'ui_connection_connecting_title',
  CONNECTION_CONNECTING_DESCRIPTION = 'ui_connection_connecting_description',
  CONNECTION_FAILED_TITLE = 'ui_connection_failed_title',
  CONNECTION_FAILED_DESCRIPTION = 'ui_connection_failed_description',
  CONNECTION_CONTEXT_FAILED_TITLE = 'ui_connection_context_failed_title',
  CONNECTION_CONTEXT_FAILED_DESCRIPTION = 'ui_connection_context_failed_description',
  CONNECTION_ENDPOINT_INVALID_TITLE = 'ui_connection_endpoint_invalid_title',
  CONNECTION_ENDPOINT_INVALID_DESCRIPTION = 'ui_connection_endpoint_invalid_description',
  CONNECTION_MATERIAL_FAILED_TITLE = 'ui_connection_material_failed_title',
  CONNECTION_MATERIAL_FAILED_DESCRIPTION = 'ui_connection_material_failed_description',
  CONNECTION_HANDSHAKE_SENT_TITLE = 'ui_connection_handshake_sent_title',
  CONNECTION_HANDSHAKE_SENT_DESCRIPTION = 'ui_connection_handshake_sent_description',
  CONNECTION_IDENTITY_VERIFIED_TITLE = 'ui_connection_identity_verified_title',
  CONNECTION_IDENTITY_VERIFIED_DESCRIPTION = 'ui_connection_identity_verified_description',
  CONNECTION_SAVED_TITLE = 'ui_connection_saved_title',
  CONNECTION_SAVED_DESCRIPTION = 'ui_connection_saved_description',
  CONNECTION_SYNC_READY_TITLE = 'ui_connection_sync_ready_title',
  CONNECTION_SYNC_READY_DESCRIPTION = 'ui_connection_sync_ready_description',
  CONNECTION_STOPPED_TITLE = 'ui_connection_stopped_title',
  CONNECTION_STOPPED_DESCRIPTION = 'ui_connection_stopped_description',
  CONNECTION_REVOKED_TITLE = 'ui_connection_revoked_title',
  CONNECTION_REVOKED_DESCRIPTION = 'ui_connection_revoked_description',
  CONNECTION_SYNC_INIT_FAILED_TITLE = 'ui_connection_sync_init_failed_title',
  CONNECTION_SYNC_INIT_FAILED_DESCRIPTION = 'ui_connection_sync_init_failed_description',
  CONNECTION_RECEIVED_TITLE = 'ui_connection_received_title',
  CONNECTION_RECEIVED_DESCRIPTION = 'ui_connection_received_description',
  CONNECTION_RECEIVE_DUPLICATE_TITLE = 'ui_connection_receive_duplicate_title',
  CONNECTION_RECEIVE_DUPLICATE_DESCRIPTION = 'ui_connection_receive_duplicate_description',
  CONNECTION_RECEIVE_PAUSED_TITLE = 'ui_connection_receive_paused_title',
  CONNECTION_RECEIVE_PAUSED_DESCRIPTION = 'ui_connection_receive_paused_description',
  CONNECTION_HISTORY_SYNC_TITLE = 'ui_connection_history_sync_title',
  CONNECTION_HISTORY_SYNC_DESCRIPTION = 'ui_connection_history_sync_description',
  OUTBOUND_NONE = 'ui_outbound_none',
  OUTBOUND_READ_FAILED = 'ui_outbound_read_failed',
  OUTBOUND_CONFIRMED = 'ui_outbound_confirmed',
  OUTBOUND_PENDING = 'ui_outbound_pending',
  OUTBOUND_QUEUED = 'ui_outbound_queued',
  DISCOVERY_WAITING = 'ui_discovery_waiting',
  DISCOVERY_UNAVAILABLE = 'ui_discovery_unavailable',
  DISCOVERY_SEARCHING = 'ui_discovery_searching',
  DISCOVERY_FOUND = 'ui_discovery_found',
  DISCOVERY_STOPPED = 'ui_discovery_stopped',
  POC_TRANSPORT_IDLE = 'ui_poc_transport_idle',
  POC_CONNECTING = 'ui_poc_connecting',
  POC_CONNECTED = 'ui_poc_connected',
  POC_CLOSED = 'ui_poc_closed',
  POC_FAILED = 'ui_poc_failed',
  POC_INVALID = 'ui_poc_invalid',
  POC_DISCONNECTED = 'ui_poc_disconnected',
  POC_RECENT_MISSING = 'ui_poc_recent_missing',
  POC_BACKGROUND = 'ui_poc_background',
  POC_DIAGNOSTICS = 'ui_poc_diagnostics',
  SOURCE_NONE = 'ui_source_none',
  SOURCE_DESKTOP = 'ui_source_desktop',
  SOURCE_DESKTOP_DEVICE = 'ui_source_desktop_device',
  SOURCE_SPACE_DEVICE = 'ui_source_space_device'
}

export enum UiMessageParameterName {
  COUNT = 'count',
  BYTE_LENGTH = 'byteLength',
  MAX_BYTES = 'maxBytes',
  ENDPOINT = 'endpoint',
  VERSION = 'version',
  STORED_COUNT = 'storedCount',
  DUPLICATE_COUNT = 'duplicateCount',
  GAP_COUNT = 'gapCount',
  DEVICE_SHORT_ID = 'deviceShortId'
}

export interface UiMessageParameter {
  name: string;
  value: string | number;
}

export interface UiMessageDescriptor {
  code: string;
  parameters: UiMessageParameter[];
}

export function uiParameter(name: UiMessageParameterName, value: string | number): UiMessageParameter {
  return { name, value };
}

export function uiMessage(
  code: UiMessageCode,
  parameters: UiMessageParameter[] = []
): UiMessageDescriptor {
  const safeParameters: UiMessageParameter[] = [];
  for (let index = 0; index < parameters.length; index += 1) {
    const parameter = parameters[index];
    if (!isSafeParameterName(parameter.name)) {
      throw new Error('unsafe ui message parameter');
    }
    if (typeof parameter.value === 'string' && parameter.value.length > 160) {
      throw new Error('unsafe ui message parameter value');
    }
    safeParameters.push({ name: parameter.name, value: parameter.value });
  }
  return { code, parameters: safeParameters };
}

export function cloneUiMessage(message: UiMessageDescriptor): UiMessageDescriptor {
  return {
    code: message.code,
    parameters: message.parameters.map((parameter: UiMessageParameter): UiMessageParameter => ({
      name: parameter.name,
      value: parameter.value
    }))
  };
}

function isSafeParameterName(name: string): boolean {
  return name === UiMessageParameterName.COUNT ||
    name === UiMessageParameterName.BYTE_LENGTH ||
    name === UiMessageParameterName.MAX_BYTES ||
    name === UiMessageParameterName.ENDPOINT ||
    name === UiMessageParameterName.VERSION ||
    name === UiMessageParameterName.STORED_COUNT ||
    name === UiMessageParameterName.DUPLICATE_COUNT ||
    name === UiMessageParameterName.GAP_COUNT ||
    name === UiMessageParameterName.DEVICE_SHORT_ID;
}
