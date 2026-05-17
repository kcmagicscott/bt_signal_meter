/// Named constants for the GATT service / characteristic UUIDs we reach for
/// repeatedly. Using these instead of raw string literals prevents typos
/// (one wrong hex digit is silent — no compile error, just an empty match)
/// and makes the intent of any UUID-check site obvious at a glance.
///
/// All values are in lowercase 128-bit form (the format flutter_blue_plus
/// surfaces from `.serviceUuid.str` etc.).
library;

// --- Standard services (Bluetooth SIG-assigned 16-bit, expanded) ----------

const String kGenericAccessServiceUuid =
    '00001800-0000-1000-8000-00805f9b34fb';
const String kGenericAttributeServiceUuid =
    '00001801-0000-1000-8000-00805f9b34fb';

/// 0x180A — Device Information service. Holds Manufacturer Name,
/// Model Number, Firmware/Hardware Revision characteristics.
const String kDeviceInformationServiceUuid =
    '0000180a-0000-1000-8000-00805f9b34fb';

/// 0x180D — Heart Rate service.
const String kHeartRateServiceUuid =
    '0000180d-0000-1000-8000-00805f9b34fb';

/// 0x180F — Battery service. Exposes the 0x2A19 Battery Level
/// characteristic (single-byte percentage).
const String kBatteryServiceUuid = '0000180f-0000-1000-8000-00805f9b34fb';

/// 0x1812 — Human Interface Device service. Set by BLE keyboards, mice,
/// gamepads.
const String kHidServiceUuid = '00001812-0000-1000-8000-00805f9b34fb';

/// 0x181A — Environmental Sensing service. Used by Xiaomi LYWSD03MMC
/// devices flashed with the ATC/pvvx custom firmware as the carrier for
/// temperature/humidity broadcasts.
const String kEnvironmentalSensingServiceUuid =
    '0000181a-0000-1000-8000-00805f9b34fb';

/// 0xFD6F — Exposure Notification (COVID-era contact tracing).
const String kExposureNotificationServiceUuid =
    '0000fd6f-0000-1000-8000-00805f9b34fb';

/// 0xFE2C — Google Fast Pair. Service data carries a 3-byte product
/// model ID followed by optional account-key payload.
const String kFastPairServiceUuid =
    '0000fe2c-0000-1000-8000-00805f9b34fb';

/// 0xFE95 — Xiaomi Mijia native MiBeacon advertising frame.
const String kXiaomiMiBeaconServiceUuid =
    '0000fe95-0000-1000-8000-00805f9b34fb';

/// 0xFE9F — Google generic.
const String kGoogleServiceUuid =
    '0000fe9f-0000-1000-8000-00805f9b34fb';

/// 0xFEAA — Eddystone beacon framework. Service data carries the frame
/// type (UID / URL / TLM / EID) and payload.
const String kEddystoneServiceUuid =
    '0000feaa-0000-1000-8000-00805f9b34fb';

/// 0xFEF3 — Older Google Fast Pair service UUID. Modern adverts use
/// 0xFE2C; this is kept around for legacy device support.
const String kFastPairLegacyServiceUuid =
    '0000fef3-0000-1000-8000-00805f9b34fb';

// --- Standard characteristics --------------------------------------------

const String kDeviceNameCharUuid = '00002a00-0000-1000-8000-00805f9b34fb';
const String kAppearanceCharUuid = '00002a01-0000-1000-8000-00805f9b34fb';
const String kBatteryLevelCharUuid = '00002a19-0000-1000-8000-00805f9b34fb';
const String kSystemIdCharUuid = '00002a23-0000-1000-8000-00805f9b34fb';
const String kModelNumberCharUuid = '00002a24-0000-1000-8000-00805f9b34fb';
const String kSerialNumberCharUuid = '00002a25-0000-1000-8000-00805f9b34fb';
const String kFirmwareRevisionCharUuid =
    '00002a26-0000-1000-8000-00805f9b34fb';
const String kHardwareRevisionCharUuid =
    '00002a27-0000-1000-8000-00805f9b34fb';
const String kSoftwareRevisionCharUuid =
    '00002a28-0000-1000-8000-00805f9b34fb';
const String kManufacturerNameCharUuid =
    '00002a29-0000-1000-8000-00805f9b34fb';
const String kCurrentTimeCharUuid = '00002a2b-0000-1000-8000-00805f9b34fb';
const String kHeartRateMeasurementCharUuid =
    '00002a37-0000-1000-8000-00805f9b34fb';
const String kBodySensorLocationCharUuid =
    '00002a38-0000-1000-8000-00805f9b34fb';
const String kPnpIdCharUuid = '00002a50-0000-1000-8000-00805f9b34fb';
