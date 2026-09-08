// DECLARATION-ONLY research module for the exact v1.2.35 binary. Emit a
// .swiftmodule ONLY; never compile/link these placeholder class definitions.
// Original class objects come exclusively from the signed SDK. No constructors
// or properties are exposed here because their full resilient ABI is unknown.
import Foundation
public final class RNCoreConnect { private init() {} }
public final class RNDevice { private init() {} }
public final class RNMessage { private init() {} }

// Original descriptor 0x184ecc: class-bound, five requirements in this order.
// The generated conformance references the ORIGINAL RayneoNet protocol symbol,
// unlike a same-shaped protocol declared in the application module.
public protocol RNMessageDelegate: AnyObject {
    func message(_ core: RNCoreConnect, receive: RNMessage)
    func message(_ core: RNCoreConnect, deviceListChanged: [RNDevice], _ reason: String)
    func message(_ core: RNCoreConnect, sendSuccess: RNMessage)
    func message(_ core: RNCoreConnect, sendError: RNMessage, _ code: Int, _ reason: String)
    func messageDecryptFail(_ core: RNCoreConnect, device: RNDevice,
                            sourceData: Data, sourceLen: Int, destLen: Int)
}
