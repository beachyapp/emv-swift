//
//  BLEListViewController.swift
//  EMV_reader
//
//  Created by Piotr Ilski on 10.10.2018.
//  Copyright © 2018 Beachy. All rights reserved.
//
import CoreBluetooth
import UIKit

class BLEListViewController: UIViewController {
    var devices: Set<BLEDevice> = []
    var selectedDevice: BLEDevice? = nil
    
    var ble: BLE!
    var emv: EmvDevice!
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var selectedDeviceLabel: UILabel!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var listeningButton: UIButton!
    
    @IBOutlet weak var consoleTextVIew: UITextView!
    
    @IBAction func startListeningLoop(_ sender: UIButton) {
        do {
            let res = try emv.readCC(0)
            if res {
                statusUpdate(status: "Waiting for swipe/connection")
            }
        } catch EmvError.cannotParseCardData(
            let message) {
            statusUpdate(status: message)
        } catch EmvError.cannotStartTransaction(
            let message) {
            statusUpdate(status: message)
        } catch EmvError.deviceIsNotConnected {
            statusUpdate(status: "Device not connected")
        } catch {
            statusUpdate(status: error.localizedDescription)
        }
    }
    
    @IBAction func connect(_ sender: UIButton) {
        if (selectedDevice != nil) {
            let isConnecting = emv.connect(uuid: selectedDevice!.getIdentifier())
            // emv.connect(friendlyName: selectedDevice!.getName()())
            
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
        
        emv = EmvDevice()
        emv.onEmvConnected = { [weak self] () in self?.statusUpdate(status: "EMV Reader connected")
            
            self?.connectButton.isEnabled = false
            self?.listeningButton.isEnabled = true
        }
        emv.onEmvDisconnected = { [weak self] () in self?.statusUpdate(status: "EMV Reader disconnected")
            
            self?.connectButton.isEnabled = true
            self?.listeningButton.isEnabled = false
        }
        emv.onEmvSendMessage =  { [weak self] (message: String) in self?.statusUpdate(status: message) }
        
        emv.onEmvDataParseError = { [weak self] (errorMessage: String) in self?.statusUpdate(status: errorMessage) }
        emv.onEmvDataReceived = {
            [weak self] (data: String) in self?.receivedCCData(data)
        }
        
        ble = BLE()
        ble.onBLEStateUpdate = { [weak self] (status: String) in
            self?.statusUpdate(status: status)
        }
        ble.onBLEAvailableDevicesListUpdate = { [weak self] (list: Set<BLEDevice>) in
            self?.listUpdate(list: list)
        }
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

extension BLEListViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sortedDevices = self.devices.sorted(by: { $0.name < $1.name })
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
        
        let sortedDevices = self.devices.sorted(by: { $0.name < $1.name })
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
