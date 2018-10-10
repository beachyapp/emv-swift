//
//  BLEListViewController.swift
//  EMV_reader
//
//  Created by Piotr Ilski on 10.10.2018.
//  Copyright © 2018 Beachy. All rights reserved.
//
import CoreBluetooth
import UIKit


extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }
    
    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return map { String(format: format, $0) }.joined()
    }
}


class BLEListViewController: UIViewController {
    var devices: Set<BLEDevice> = []
    var centralManager: CBCentralManager!
    var selectedDevice: BLEDevice? = nil

    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var selectedDeviceLabel: UILabel!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var listeningButton: UIButton!
    
    
    @IBAction func startListeningLoop(_ sender: UIButton) {
        
        IDT_VP3300
            .sharedController()
            .emv_disableAutoAuthenticateTransaction(false)
//        let rt = IDT_VP3300.sharedController()
//            .msr_startMSRSwipe()
//
//        print(rt)
//
        let rt = IDT_VP3300
            .sharedController()
            .device_startTransaction(1.00,
                                     amtOther: 0,
                                     type: 0,
                                     timeout: 60,
                                     tags: nil,
                                     forceOnline: false,
                                     fallback: true)

        if RETURN_CODE_DO_SUCCESS == rt {
            print("Start transaction command accepted")
            print(rt)
        } else {
            print("Start EMV transaction error")
            print(rt)
        }
    }
    
    @IBAction func connect(_ sender: UIButton) {
        if (selectedDevice != nil) {
//             IDT_VP3300
//                .sharedController()
//                .device_setBLEFriendlyName(selectedDevice?.getName())

            IDT_VP3300
                .sharedController()
                .device_enableBLEDeviceSearch(
                    selectedDevice!.getIdentifier())
            print("connecting... \(String(describing: selectedDevice?.identifier))")
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        connectButton.isEnabled = false;

        IDT_VP3300.sharedController().delegate = self
        
        centralManager = CBCentralManager(delegate: self,
                                          queue: DispatchQueue.main)
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
        
        print("Selected device: \(String(describing: selectedDevice?.getName()))")
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        selectedDevice = nil;
        
        print("Selected device: \(String(describing: selectedDevice))")
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
            print("unknown state")
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
//            print("REFRESHING...")
        }
    }
}

extension BLEListViewController: IDT_VP3300_Delegate {
    @objc func completeEMV() {
        NotificationCenter.default.post(name: Notification.Name(rawValue: "completeEMV"), object: nil)
    }
    
    @objc func startEMV() {
        NotificationCenter.default.post(name: Notification.Name(rawValue: "startEMV"), object: nil)
    }
    
    func lcdDisplay(_ mode: Int32, lines: [Any]!) {
        print("LCD DISPLAY: \(String(describing: lines))")
    }
    
    func deviceMessage(_ message: String!) {
        print("MESSAGE: \(message ?? String())");
    }
    
    func swipeMSRData(_ cardData: IDTMSRData!) {
        print("---- DATA SWIPED ---")
        print("Track 3: \(String(describing: cardData.track3))");
        print("Encoded Track 1: \(cardData.encTrack1.description)");
        print("Encoded Track 2: \(cardData.encTrack2.description)");
        print("Encoded Track 3: \(cardData.encTrack3.description)");
        print("Hash Track 1: \(cardData.hashTrack1.description)");
        print("Hash Track 2: \(cardData.hashTrack2.description)");
        print("Hash Track 3: \(cardData.hashTrack3.description)");

        if cardData.unencryptedTags != nil {
            print("Unencrypted Tags: \( cardData.unencryptedTags.description)")
        }

        if cardData.encryptedTags != nil {
            print("Encrypted Tags: \(cardData.encryptedTags.description)")
        }

        if cardData.maskedTags != nil {
            print("Masked Tags: \(cardData.maskedTags.description)")
        }
    }
    
    func emvTransactionData(_ emvData: IDTEMVData!, errorCode error: Int32) {
//        print("GOT THE TRANSACTION DATA: \(emvData.cardType)")
//        print("RES: \(emvData.resultCode) \(emvData.resultCodeV2)")
//
//
//        print("--------------------")
//        print("        TAGS        ")
//        print(emvData.unencryptedTags != nil ? emvData.unencryptedTags.description : "N/A")
//        print(emvData.encryptedTags)
//        print(emvData.maskedTags)
//
//        print("--------------------")
//        print("        CDA1        ")
//        print(emvData.cardData)
//
//        print("--------------------")
//        print("        CDA2        ")
//        print(emvData.cardData?.cardData)
        
        var loopData = true
        let autocompleteStatus = true
        
        if emvData.resultCodeV2 == EMV_RESULT_CODE_V2_TIME_OUT {
            
        }
        
        if emvData.resultCodeV2 != EMV_RESULT_CODE_V2_NO_RESPONSE {
            print("EMV_RESULT_CODE_V2_RESPONSE: \(emvData.resultCodeV2.rawValue)")
        }
        
        if emvData.resultCodeV2 == EMV_RESULT_CODE_V2_GO_ONLINE {
            print("ONLINE REQUEST")
            loopData = false
            
            if autocompleteStatus {
                Timer.scheduledTimer(timeInterval: 0.5,
                                     target: self,
                                     selector: #selector(completeEMV),
                                     userInfo: nil,
                                     repeats: false)
            }
        }
        
        if emvData.resultCodeV2 == EMV_RESULT_CODE_V2_START_TRANS_SUCCESS {
            loopData = false
            print("Start success: authentication required")
        }
        
        if emvData.resultCodeV2 == EMV_RESULT_CODE_V2_APPROVED || emvData.resultCodeV2 == EMV_RESULT_CODE_V2_APPROVED_OFFLINE {
            print("APPROVED");
        }
        
        if emvData.resultCodeV2 == EMV_RESULT_CODE_V2_MSR_SUCCESS {
            print("MSR Data Captured")
        }
        
        if emvData.cardType == 0 {
            print("CONTACT")
        }
        
        if emvData.cardType == 1 {
            print("CONTACTLESS")
        }
        
        if emvData.unencryptedTags != nil {
            print("Unencrypted Tags: \(emvData.unencryptedTags.description)")
        }
        
        if emvData.encryptedTags != nil {
            print("Encrypted Tags: \(emvData.encryptedTags.description)")
        }
        
        if emvData.maskedTags != nil {
            print("Masked Tags: \(emvData.maskedTags.description)")
        }
        
        if emvData.hasAdvise {
            print("Response has advise request")
        }
        
        if emvData.hasReversal {
            print("Response has reversal request")
        }
        
        if loopData {
            Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(startEMV), userInfo: nil, repeats: false)
        }
        
        if (emvData.cardData != nil) {
            print("CARD DATA: \(emvData.cardData)")
            var ksn = emvData.cardData.ksn != nil ? emvData.cardData.ksn.hexEncodedString() : "nth"
            print("KSN:  \(ksn)")
            var ses = emvData.cardData.sessionID != nil ? emvData.cardData.sessionID.hexEncodedString() : "nth"
            print("SESSION ID:  \(ses)")
            var rsn = emvData.cardData.rsn != nil ? emvData.cardData.rsn : "nth"
            print("RSN:  \(rsn)")
            print("STATUS:  \(emvData.cardData.readStatus)")
        }
    }
    
    func deviceConnected() {
        print("DEVICE CONNECTED")
        
        IDT_VP3300
            .sharedController()
            .device_disableBLEDeviceSearch()
        
       
    }
    
    func deviceDisconnected() {
        print("DEVICE DISCONNECTED")
    }
    
    
}
