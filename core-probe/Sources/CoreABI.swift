import Foundation
import CoreBluetooth

// Research-only ABI facade for RayneoNet v1.2.35 from iOS app 1.0.2 (67).
// No private Apple APIs. These are original third-party framework exports.
// Opaque handles must ONLY come from the library; never allocate these classes.
// Swift String and reference return layouts verified against exported signatures.
@_silgen_name("$s9RayneoNet13RNCoreConnectC5shareACvgZ")
func coreShared() -> CoreHandle

@_silgen_name("$s9RayneoNet13RNCoreConnectC10SDKVersionSSSgvgZ")
func coreVersion() -> String?

func sdkModelCatalog() -> [String: Any]? {
    guard let address = RNProbeCatalogAddress() else { return nil }
    typealias Catalog = @convention(thin) () -> [String: Any]?
    return unsafeBitCast(address, to: Catalog.self)()
}

func convertPeripheral(_ peripheral: NSObject) -> DeviceHandle? {
    guard let address = RNProbeConverterAddress() else { return nil }
    typealias Converter = @convention(thin) (NSObject?) -> DeviceHandle?
    return unsafeBitCast(address, to: Converter.self)(peripheral)
}

final class CoreHandle {
    private init() { fatalError("Opaque library handle") }

    // Original Runner callsites 0x101822d28 and 0x10184439c explicitly pass w3=0.
    // RNShareTarget is a two-case no-payload byte enum in this exact SDK image.
    @_silgen_name("$s9RayneoNet13RNCoreConnectC9fileShare4send8deviceId6target5extraSSSg10Foundation3URLV_SSAA13RNShareTargetOSStF")
    func shareFile(_ url: URL, _ device: String, _ target: UInt8, _ extra: String) -> String?
    @_silgen_name("$s9RayneoNet13RNCoreConnectC9fileShare10cancelSend6taskIdySS_SStF")
    func cancelShare(_ device: String, _ task: String)

    @_silgen_name("$s9RayneoNet13RNCoreConnectC12setAccountIdyySSF")
    func setAccountID(_ value: String)

    @_silgen_name("$s9RayneoNet13RNCoreConnectC13bondedDevicesSayAA8RNDeviceCGSgvg")
    func bondedDevices() -> [DeviceHandle]?

    @_silgen_name("$s9RayneoNet13RNCoreConnectC20currentLinkedDevicesSayAA8RNDeviceCGSgvg")
    func linkedDevices() -> [DeviceHandle]?

    @_silgen_name("$s9RayneoNet13RNCoreConnectC10findDeviceyAA8RNDeviceCSgSSF")
    func findDevice(_ id: String) -> DeviceHandle?

    // Only nil filter is passed: optional-array ABI is one null reference.
    // Do not pass a UInt8 array as RNDiscoveryType without recovering that enum.
    @_silgen_name("$s9RayneoNet13RNCoreConnectC13discoverStart7filters11retrieveIdsySayAA15RNDiscoveryTypeOGSg_SaySSGSgtKF")
    fileprivate func discoverABI(_ filters: [UInt8]?, _ retrieveIDs: [String]?) throws

    func discover() throws { try discoverABI(nil, nil) }

    // RNDeviceConnectType.rawValue getter disassembly: enum byte 0 => "ble".
    @_silgen_name("$s9RayneoNet13RNCoreConnectC3cmd7connect6userId_yAA8RNDeviceC_SSAA0iD4TypeOtKF")
    fileprivate func connectABI(_ device: DeviceHandle, _ userID: String, _ type: UInt8) throws

    func connectBLE(_ device: DeviceHandle) throws { try connectABI(device, "", 0) }

    @_silgen_name("$s9RayneoNet13RNCoreConnectC3cmd7unboundyAA8RNDeviceC_tKF")
    func unbind(_ device: DeviceHandle) throws

    // cmd(getBTState:) is deliberately NOT exposed: this build's dispatcher
    // path only logs and releases objects (0x55740-0x55914), without sending.
}

final class DeviceHandle {
    private init() { fatalError("Opaque library handle") }

    @_silgen_name("$s9RayneoNet8RNDeviceC2idSSvg")
    func deviceID() -> String

    @_silgen_name("$s9RayneoNet8RNDeviceC4nameSSvg")
    func name() -> String

    @_silgen_name("$s9RayneoNet8RNDeviceC11isConnectedSbvg")
    func isConnected() -> Bool

    // Verified getter loads one byte, enum encoding 9 is accepted by isConnected.
    @_silgen_name("$s9RayneoNet8RNDeviceC8bleStateAA03BleE0Ovg")
    func bleStateByte() -> UInt8

    // Exported getter retains the real NSObject-based RNPeripheral (0x4f558).
    // Do not allocate or reinterpret a replacement object.
    @_silgen_name("$s9RayneoNet8RNDeviceC5rnPerAA12RNPeripheralCvg")
    func transport() -> NSObject
}

extension NSObject {
    // Only call these exports on an RNPeripheral returned by DeviceHandle.
    @_silgen_name("$s9RayneoNet12RNPeripheralC10peripheralSo12CBPeripheralCSgvg")
    func rnSDKPeripheral() -> CBPeripheral?

    @_silgen_name("$s9RayneoNet12RNPeripheralC8bleStateAA010BLEConnectE0Ovg")
    func rnSDKTransportState() -> UInt8
}
