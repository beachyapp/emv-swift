//
//  BLEListViewController.swift
//  EMV_reader
//
//  Created by Piotr Ilski on 10.10.2018.
//  Copyright © 2018 Beachy. All rights reserved.
//
import UIKit


class BLEListViewController: UIViewController {
    private var isConnecting: Bool = false;
    private var isConnected: Bool = false;
    
    var devices: Set<BLEDevice> = []
    var selectedDevice: BLEDevice? = nil
    var connectedTime: DispatchTime = DispatchTime.now()
    var disconnectedTime: DispatchTime = DispatchTime.now()
    var b: BeachyEMVReaderControl = BeachyEMVReaderControl.shared
    
    @IBOutlet weak var connectionStatus: UILabel!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var selectedDeviceLabel: UILabel!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var listeningButton: UIButton!
    
    @IBOutlet weak var consoleTextVIew: UITextView!
    
    @IBAction func startListeningLoop(_ sender: UIButton) {
        let res = b.readCardData(0)
            
        statusUpdate(status: "Waiting for swipe/connection: \(res)")
    }
    
    @IBAction func connect(_ sender: UIButton) {
        guard let uuid = selectedDevice?.getIdentifier() else { return; }
        
        connect(uuid: uuid)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    
        connectButton.isEnabled = false
        listeningButton.isEnabled = false
        
        b.delegate = self
    }
    
    func receivedCCData(_ message: String) {
        let alert = UIAlertController(
            title: "Got it!",
            message: message,
            preferredStyle: .alert)

        alert.addAction(UIAlertAction(
            title: "Ok",
            style: .default,
            handler: nil))

        self.present(alert, animated: true)
    }
    
    func statusUpdate(status: String) {
        printDebugMessage(status)
    }
    
    func listUpdate(list: Set<BLEDevice>) {
        self.devices = list;
        self.tableView.reloadData()
    }
    
    func printDebugMessage(_ message: String) {
        consoleTextVIew.text = consoleTextVIew.text + "\n" + message
    }
    
    func autoConnect(list: Set<BLEDevice>) {
        let filtered = list.filter { $0.isSupportedEmv }
        
        if filtered.count > 0 && !isConnected {
            guard let uuid = filtered.first?.getIdentifier() else { return; }

            connect(uuid: uuid)
        }
    }
    
    private func connect(uuid: UUID) {
        isConnecting = b.connect(uuid: uuid)
        isConnected = false
        
        if (isConnecting) {
            updateConnectionStatus("connecting")
            statusUpdate(status: "Connecting ...")
            connectButton.isEnabled = false
        } else {
            statusUpdate(status: "Unable to connect")
            connectButton.isEnabled = true
        }
    }
    
    private func updateConnectionStatus(_ status: String) {
        self.connectionStatus.text = status;
    }
}

extension BLEListViewController: BeachyEMVReaderControlProtocol {
    
    func readerConnected() {
        connectedTime = DispatchTime.now()
        
        isConnecting = false
        isConnected = true
        connectButton.isEnabled = false
        listeningButton.isEnabled = true
        
        updateConnectionStatus("connected")
        
        let ret = b.configureSleepModeAndPowerOffTimes(
            sleepTimeInSec: 60,
            powerOffTimeInSec: 90)
        let device = IDT_VP3300.sharedController()?.device_connectedBLEDevice()
        let code = IDT_VP3300.sharedController()?.device_getResponseCodeString(Int32(ret))
        
        statusUpdate(status: """
            Reder connected, UUID: \(device?.uuidString ?? "Unknown")
            Configuration result: \(ret)
            Human readable error: \(code ?? "Unknown")
        """)
    }
    
  
    func bluetoothAvailableDevicesListUpdate(devices: Set<BLEDevice>) {
        listUpdate(list: devices)
        autoConnect(list: devices)
    }

    func bluetoothStatusUpdate(status: String) {
        debugPrint("BLE status update: \(status)")
        statusUpdate(status: status)
    }

    func readerDisconnected() {
        disconnectedTime = DispatchTime.now();
        
        updateConnectionStatus("disconnected")
        isConnecting = false
        isConnected = false
        connectButton.isEnabled = selectedDevice != nil
        listeningButton.isEnabled = false
        
        let nanoTime = disconnectedTime.uptimeNanoseconds - connectedTime.uptimeNanoseconds
        let timeInterval = Double(nanoTime) / 1_000_000_000
        
        statusUpdate(status: "EMV disconnected after \(timeInterval) seconds")
    }

    func readerDataParseError(errorMessage: String) {
        statusUpdate(status: errorMessage)
    }

    func readerData(data: String) {
        receivedCCData(data)
    }

    func readerSendsMessage(message: String) {
        statusUpdate(status: message)
    }
}

extension BLEListViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sortedDevices = self.devices.sorted(by: { $0.getName() < $1.getName() })
        let device = sortedDevices[indexPath.row]
        
        if (device.isSupportedEmv) {
            selectedDevice = device;
        }
        
        if (selectedDevice != nil) {
            connectButton.isEnabled = true
            selectedDeviceLabel.text = selectedDevice!.getName()
        } else {
            connectButton.isEnabled = false
            selectedDeviceLabel.text = "nothing selected"
        }
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        selectedDevice = nil;
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.devices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "BLEDeviceTableViewCell"
        
        guard let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as? BLEDeviceTableViewCell  else {
            fatalError("The dequeued cell is not an instance of BLEDeviceTableViewCell.")
        }
        
        let sortedDevices = self.devices.sorted(by: { $0.getName() < $1.getName() })
        let device = sortedDevices[indexPath.row]
        
        cell.nameLabel.text = device.getName()
        cell.isEMVReader.text = device.isSupportedEmv ? "EMV" : ""
        cell.selectionStyle = .none
        if (device.isSupportedEmv) {
            cell.selectionStyle = .default
            cell.nameLabel.textColor = UIColor(displayP3Red: 46/255,
                                               green: 139/255,
                                               blue: 87/255,
                                               alpha: 0.85)
        }
        
        return cell
    }
}
