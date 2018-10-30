//
//  BLEListViewController.swift
//  EMV_reader
//
//  Created by Piotr Ilski on 10.10.2018.
//  Copyright © 2018 Beachy. All rights reserved.
//
import UIKit
//import BeachyEMVReaderControl
import BeachyEMVReaderControl
//
//class BLEDevice: NSObject {
//    var name: String = ""
//    var isSupportedEmv: Bool = false
//
//    func getName() -> String {
//        return ""
//    }
//
//    func getIdentifier() -> UUID {
//        return UUID.init(uuidString: "ABC")!
//    }
//}

class BLEListViewController: UIViewController {
    var devices: Set<BLEDevice> = []
    var selectedDevice: BLEDevice? = nil
    
//    var ble: BLE!
//    var emv: EmvDevice!
    var b: BeachyEMVReaderControl = BeachyEMVReaderControl.shared
    
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
        if (selectedDevice != nil) {
            let isConnecting = b.connect(uuid: selectedDevice!.getIdentifier())

            if (isConnecting) {
                statusUpdate(status: "Connecting ...")
                connectButton.isEnabled = false

            } else {
                statusUpdate(status: "Unable to connect")
                connectButton.isEnabled = true
            }
        }
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
        print("STATUS: \(status)")
        printDebugMessage(status)
    }
    
    func listUpdate(list: Set<BLEDevice>) {
        self.devices = list;
        self.tableView.reloadData()
    }
    
    func printDebugMessage(_ message: String) {
        consoleTextVIew.text = consoleTextVIew.text + "\n" + message
    }
}

extension BLEListViewController: BeachyEMVReaderControlProtocol {
    func bluetoothAvailableDevicesListUpdate(devices: [BLEDevice]) {
        listUpdate(list: Set(devices))
    }

    func bluetoothStatusUpdate(status: String) {
        statusUpdate(status: status)
    }


    func readerConnected() {
        connectButton.isEnabled = false
        listeningButton.isEnabled = true
    }

    func readerDisconnected() {
        connectButton.isEnabled = true
        listeningButton.isEnabled = false
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
