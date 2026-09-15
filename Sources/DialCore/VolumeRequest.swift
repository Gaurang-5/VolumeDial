public struct VolumeRequest {
    public let outputID: UInt32
    public let value: Double
    public init(outputID: UInt32, value: Double) {
        self.outputID = outputID
        self.value = DialMath.clamp(value)
    }
    public func canApply(currentOutputID: UInt32, isSwitching: Bool) -> Bool {
        !isSwitching && outputID != 0 && outputID == currentOutputID
    }
}
