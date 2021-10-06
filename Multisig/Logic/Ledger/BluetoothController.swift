//
//  BluetoothController.swift
//  Multisig
//
//  Created by Moaaz on 7/26/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import Foundation
import CoreBluetooth

class BaseBluetoothDevice {
    var identifier: UUID { preconditionFailure() }
    var name: String { preconditionFailure() }
}

class BluetoothDevice: BaseBluetoothDevice {
    let peripheral: CBPeripheral

    override var name: String {
        peripheral.name ?? "Unknown device"
    }

    override var identifier: UUID {
        peripheral.identifier
    }

    var readCharacteristic: CBCharacteristic? = nil
    var writeCharacteristic: CBCharacteristic? = nil
    var notifyCharacteristic: CBCharacteristic? = nil

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }
}

protocol SupportedDevice {
    var uuid: CBUUID { get }
    var notifyUuid: CBUUID { get }
    var writeUuid: CBUUID { get }
}

struct LedgerNanoXDevice: SupportedDevice {
    var uuid: CBUUID { CBUUID(string: "13d63400-2c97-0004-0000-4c6564676572") }
    var notifyUuid: CBUUID { CBUUID(string: "13D63400-2C97-0004-0001-4C6564676572") }
    var writeUuid: CBUUID { CBUUID(string: "13d63400-2c97-0004-0002-4c6564676572") }
}

protocol BluetoothControllerDelegate: AnyObject {
    func bluetoothControllerDidFailToConnectBluetooth(error: DetailedLocalizedError)
    func bluetoothControllerDidDiscover(device: BaseBluetoothDevice)
    func bluetoothControllerDidDisconnect(device: BaseBluetoothDevice, error: DetailedLocalizedError?)
}

class BaseBluetoothController: NSObject {
    weak var delegate: BluetoothControllerDelegate?
    var devices: [BaseBluetoothDevice] = []

    func scan() {
        preconditionFailure()
        // can discover several times
        // -or can fail to connect
        // after discovering it can disconnect
    }

    func stopScan() {
        preconditionFailure()
        // stops scanning, i.e. no discovering will happen
    }

    func deviceFor(deviceId: UUID) -> BaseBluetoothDevice? {
        devices.first { $0.identifier == deviceId }
    }

    func sendCommand(device: BaseBluetoothDevice, command: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        preconditionFailure()
        // sends command, then async returns response - either data or error
    }
}

class BluetoothController: BaseBluetoothController {
    private var centralManager: CBCentralManager!

    typealias WriteCommand = () -> Void
    private var writeCommands = [UUID: WriteCommand]()

    typealias ResponseCompletion = (Result<Data, Error>) -> Void
    private var responses = [UUID: ResponseCompletion]()

    private var supportedDevices: [SupportedDevice] = [LedgerNanoXDevice()]
    private var supportedDeviceUUIDs: [CBUUID] { supportedDevices.compactMap { $0.uuid } }
    private var supportedDeviceNotifyUuids: [CBUUID] { supportedDevices.compactMap { $0.notifyUuid } }

    override func scan() {
        devices = []
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    override func stopScan() {
        centralManager.stopScan()
    }

    func removeDevices(peripheral: CBPeripheral) {
        devices.removeAll { d in
            if let device = d as? BluetoothDevice {
                return device.peripheral == peripheral
            }
            return false
        }
    }

    func bluetoothDevice(id: UUID) -> BluetoothDevice? {
        deviceFor(deviceId: id) as? BluetoothDevice
    }

    override func sendCommand(device: BaseBluetoothDevice, command: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let device = device as? BluetoothDevice else {
            preconditionFailure("Expecting bluetooth device")
        }
        centralManager.connect(device.peripheral, options: nil)
        writeCommands[device.peripheral.identifier] = { [weak self] in
            let adpuData = APDUController.prepareADPU(message: command)
            self?.responses[device.peripheral.identifier] = completion
            device.peripheral.writeValue(adpuData, for: device.writeCharacteristic!, type: .withResponse)
        }
    }
}

extension BluetoothController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            centralManager.scanForPeripherals(withServices: supportedDeviceUUIDs)
        case .unauthorized:
            delegate?.bluetoothControllerDidFailToConnectBluetooth(error: GSError.BluetoothIsNotAuthorized())
        default:
            delegate?.bluetoothControllerDidFailToConnectBluetooth(error: GSError.ProblemConnectingBluetoothDevice())
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        if deviceFor(deviceId: peripheral.identifier) == nil {
            let device = BluetoothDevice(peripheral: peripheral)
            devices.append(device)
            delegate?.bluetoothControllerDidDiscover(device: device)
        }

        centralManager.stopScan()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(supportedDeviceUUIDs)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let device = deviceFor(deviceId: peripheral.identifier) else { return }
        let detailedError: DetailedLocalizedError? =
            error == nil ? nil : GSError.error(description: "The Bluetooth device disconnected", error: error!)
        removeDevices(peripheral: peripheral)

        responses.forEach { deviceId, completion in
            completion(.failure("The Bluetooth device disconnected"))
        }

        delegate?.bluetoothControllerDidDisconnect(device: device, error: detailedError)
    }
}

extension BluetoothController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }

        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
                bluetoothDevice(id: peripheral.identifier)!.readCharacteristic = characteristic
            }

            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
                bluetoothDevice(id: peripheral.identifier)!.notifyCharacteristic = characteristic
            }

            if characteristic.properties.contains(.write) {
                peripheral.setNotifyValue(true, for: characteristic)
                bluetoothDevice(id: peripheral.identifier)!.writeCharacteristic = characteristic

                if let writeCommand = writeCommands[peripheral.identifier] {
                    writeCommand()
                    writeCommands.removeValue(forKey: peripheral.identifier)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if supportedDeviceNotifyUuids.contains(characteristic.uuid) {
            // skip if response is not awaited anymore
            guard let responseCompletion = responses[peripheral.identifier] else { return }

            if let error = error {
                LogService.shared.info("Failed to connect with bluetooth device", error: error)
                responseCompletion(.failure(error))
            }
            if let message = characteristic.value, let data = APDUController.parseADPU(message: message) {
                responseCompletion(.success(data))
            } else {
                LogService.shared.error(
                    "Could not parse ADPU for message: \(characteristic.value?.toHexString() ?? "nil")")
                responseCompletion(.failure(""))
            }
            
            responses.removeValue(forKey: peripheral.identifier)
        }
    }
}


class SimulatedLedgerDevice: BaseBluetoothDevice {
    let deviceID = UUID()
    let deviceName = "Simulated Ledger Nano X"

    override var identifier: UUID { deviceID }
    override var name: String { deviceName }
}

class SimulatedBluetoothController: BaseBluetoothController {
    override init() {
        super.init()
        devices = [SimulatedLedgerDevice()]
    }

    override func scan() {
        // immediately discover
        delegate?.bluetoothControllerDidDiscover(device: devices[0])
    }

    override func stopScan() {
        // do nothing
    }

    override func sendCommand(device: BaseBluetoothDevice, command: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        DispatchQueue.global().async {
            if command.starts(with: [0xe0, 0x02]) {
                // get address

                // generate random address
                var address: Address!
                repeat {
                    address = Data.randomBytes(length: 20).flatMap { Address($0) }
                } while address == nil


                let fakePublicKey = [UInt8](repeating: 1, count: 65)
                let hexAddress = address.data.toHexString().data(using: .ascii)!

                let response: [UInt8] =
                    [UInt8(fakePublicKey.count)] + fakePublicKey +
                    [UInt8(hexAddress.count)] + hexAddress
                assert(response.count == 107)
                assert(response[0] == 65)
                assert(response[66] == 40)

                completion(.success(Data(response)))
            } else {
                completion(.failure("Failed to do the command"))
            }
        }
    }
}
