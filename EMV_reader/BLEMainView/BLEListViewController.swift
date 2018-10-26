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
    var centralManager: CBCentralManager!
    var selectedDevice: BLEDevice? = nil
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var selectedDeviceLabel: UILabel!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var listeningButton: UIButton!
    
    @IBOutlet weak var consoleTextVIew: UITextView!
    
    @IBAction func startListeningLoop(_ sender: UIButton) {
        /**
         * 0xDFEE1A [N*SIZE OF TAG][TAG1][TAG2]...[TAGN]
         *
         */
//        let TLVstring = "DFEE1A03DFEE12"
//        let TLV = IDTUtility.hex(toData: TLVstring)
        IDT_VP3300
            .sharedController()
            .ctls_startTransaction()
        
        if (IDT_VP3300
            .sharedController()
            .device_isConnected(IDT_DEVICE_VP3300_IOS)) {
            
            
            IDT_VP3300.sharedController().msr_cancelMSRSwipe();
            IDT_VP3300.sharedController().device_cancelTransaction();
        
            let rt = IDT_VP3300
                .sharedController()
                .device_startTransaction(0, amtOther: 0, type: 0, timeout: 60, tags: nil, forceOnline: false, fallback: true)
            
            if RETURN_CODE_DO_SUCCESS == rt {
                printDebugMessage("Start transaction command accepted")
                printDebugMessage(String(rt.rawValue, radix: 16))
            } else {
                printDebugMessage("Start EMV transaction error")
                printDebugMessage(String(rt.rawValue, radix: 16))
            }
        } else {
            printDebugMessage("Not even connected?")
        }
        
//            .emv_startTransaction(1.00, amtOther: 0, type: 0, timeout: 60, tags: nil, forceOnline: false, fallback: true)
//            .device_startTransaction(1.00,
//                                     amtOther: 0,
//                                     type: 0,
//                                     timeout: 60,
//                                     tags: nil,
//                                     forceOnline: false,
//                                     fallback: true)
        
       
    }
    
    @IBAction func connect(_ sender: UIButton) {
        if (selectedDevice != nil) {
            
            let rt = IDT_VP3300
                .sharedController()
                .device_enableBLEDeviceSearch(
                    selectedDevice!.getIdentifier())
            
            printDebugMessage("Connecting to \(String(describing: selectedDevice?.identifier)) | ret: \(rt)")
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        connectButton.isEnabled = false
        listeningButton.isEnabled = false
        
        IDT_VP3300.sharedController().delegate = self
        
        centralManager = CBCentralManager(delegate: self,
                                          queue: DispatchQueue.main)
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

extension BLEListViewController: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            self.centralManager?.scanForPeripherals(
                withServices: nil,
                options: nil)
        case .poweredOff:
            self.centralManager?.stopScan();
        default:
            printDebugMessage("unknown state")
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        let prevCount = self.devices.count;
        
        self.devices.insert(BLEDevice(
            name: peripheral.name ?? "unknown",
            identifier: peripheral.identifier))
        
        if (self.devices.count != prevCount) {
            self.tableView.reloadData()
        }
    }
}

