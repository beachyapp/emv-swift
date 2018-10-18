//
//  BLEListViewController.swift
//  EMV_reader
//
//  Created by Piotr Ilski on 10.10.2018.
//  Copyright © 2018 Beachy. All rights reserved.
//
import CoreBluetooth
import UIKit
import CryptoSwift

class BLEListViewController: UIViewController {
    var devices: Set<BLEDevice> = []
    var centralManager: CBCentralManager!
    var selectedDevice: BLEDevice? = nil
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var selectedDeviceLabel: UILabel!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var listeningButton: UIButton!
    
    
    @IBAction func startListeningLoop(_ sender: UIButton) {
        /**
         * 0xDFEE1A [N*SIZE OF TAG][TAG1][TAG2]...[TAGN]
         *
         */
        let TLVstring = "DFEE1A03DFEE12"
        let TLV = IDTUtility.hex(toData: TLVstring)
        let rt = IDT_VP3300
            .sharedController()
            .device_startTransaction(1.00,
                                     amtOther: 0,
                                     type: 0,
                                     timeout: 60,
                                     tags: TLV,
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
            
            IDT_VP3300
                .sharedController()
                .device_enableBLEDeviceSearch(
                    selectedDevice!.getIdentifier())
            print("connecting... \(String(describing: selectedDevice?.identifier))")
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
            print("REFRESHING...")
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
        
        var loopData = true
        let autocompleteStatus = true
        
        print("RES CODE V1: \(String(emvData.resultCode.rawValue, radix: 16))")
        print("RES CODE V2: \(String(emvData.resultCodeV2.rawValue, radix: 16))")
        
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
            
            if(emvData.cardData == nil) {
                let ksnData = emvData.unencryptedTags["FFEE12"] as? Data
                
                if (ksnData != nil) {
                    let track2DataCandidate = emvData.unencryptedTags["DFEF4D"] as? Data
                    if (track2DataCandidate != nil) {
                        
                        let ret = IDT_VP3300
                            .sharedController()
                            .emv_completeOnlineEMVTransaction(true,
                                                              hostResponseTags: Data(bytes: [0xDF, 0xEE, 0x1B] as [UInt8]))
                        
                        let TLVstring = "DFEE12"
                        let TLV = IDTUtility.hex(toData: TLVstring)
                        
                        var data: NSDictionary?
                        let ret2 = IDT_VP3300
                            .sharedController()
                            .emv_retrieveTransactionResult(TLV, retrievedTags: &data)
                        
                        
                        print("--------------------------------")
//                        print("RET VAL: \(String(ret.rawValue,radix: 16)) \(String(ret2.rawValue,radix: 16))")
                        print("DATA: \(data)")
                        print("--------------------------------")
                        
                        let dataHex = track2DataCandidate!.hexEncodedString()
                            .replacingOccurrences(of: " ", with: "")
                        let keyHex = ksnData!.hexEncodedString()
                            .replacingOccurrences(of: " ", with: "")
                        
                        tryParse(encryptedData: dataHex, key: keyHex)
                    }
                }
            }
            
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
            tryParse(encryptedData: emvData.cardData!.encTrack2.hexEncodedString(),
                     key: emvData.cardData!.ksn.hexEncodedString())
            
            let TLVstring = "DFEE12"
            let TLV = IDTUtility.hex(toData: TLVstring)
            
            
            var data: NSDictionary?
            let ret2 = IDT_VP3300
                .sharedController()
                .emv_retrieveTransactionResult(TLV, retrievedTags: &data)
            
            
            print("--------------------------------")
            print("RET VAL: \(String(ret2.rawValue,radix: 16))")
            print("DATA: \(data)")
            print("--------------------------------")
        }
    }
    
    func hexToByteArray(hex: String) -> [UInt8] {
        return hex.replacingOccurrences(of: " ", with: "")
            .pairs
            .filter({$0 != ""})
            .map({
                print($0)
                return UInt8($0, radix: 16) ?? 0
            })
    }
    
    func tryParse(encryptedData: String, key: String) {
        
        do {
            let bytesDate: [UInt8] = hexToByteArray(hex: encryptedData)
            let ksn = key.replacingOccurrences(of: " ", with: "")
            
            let bdk = "0123456789ABCDEFFEDCBA9876543210"

            let decrypto = Decrypto()
            
            let sessionKey = decrypto.getKey(bdkHex: bdk, ksnHex: ksn)
            let keyData = hexToByteArray(hex: sessionKey)
            
            let d = try AES(key: keyData,
                            blockMode: CBC(iv: hexToByteArray(hex: "00000000000000000000000000000000")),
                            padding: .noPadding)
                .decrypt(bytesDate)
            
            print(hexToByteArray(hex: encryptedData))
            print(hexToByteArray(hex: key))
            
            print(d.toHexString())
            print(decrypto.hexToAscii(hex: d.toHexString()))
            
            let ccString = decrypto.hexToAscii(hex: d.toHexString())
            
            let alert = UIAlertController(
                title: "Got it!",
                message: ccString,
                preferredStyle: .alert)
            
            alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
            
            self.present(alert, animated: true)
        } catch {
            print(error)
        }
    }
    
//    func EDE3KeyExpand(key: String ) -> String {
//        switch key.count {
//        case 16:
//            let index = key.index(key.startIndex,
//                                  offsetBy: key.count/2)
//            return key + String(key[..<index])
//        case 24:
//            return key
//        default:
//            return ""
//        }
//    }
    
    func hexstringToData(hex: String) -> Data {
        return Data(hexString: hex)!
    }

    
    func deviceConnected() {
        print("DEVICE CONNECTED")
        
        IDT_VP3300
            .sharedController()
            .device_disableBLEDeviceSearch()
      
        
        let TLVstring = "5F360102DFEF4B037f7f7f"
//        "5F360102"
        let TLV = IDTUtility.hex(toData: TLVstring)
        let rt = IDT_VP3300.sharedController().emv_setTerminalData(IDTUtility.tlVtoDICT(TLV))
        print("IDTUtility.tlVtoDICT(TLV): \(IDTUtility.tlVtoDICT(TLV))")
        if RETURN_CODE_DO_SUCCESS == rt {
            print("GOOOD")
        } else {
            print("OUPS: \(String(rt.rawValue, radix: 16))")
        }
        
        listeningButton.isEnabled = true
    }
    
    func deviceDisconnected() {
        print("DEVICE DISCONNECTED")
        
        
        listeningButton.isEnabled = false
    }
    
    
}
