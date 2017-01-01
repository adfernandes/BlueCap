//
//  PeripheralManagerBeaconViewController.swift
//  BlueCap
//
//  Created by Troy Stribling on 9/28/14.
//  Copyright (c) 2014 Troy Stribling. The MIT License (MIT).
//

import UIKit
import BlueCapKit

class PeripheralManagerBeaconViewController: UITableViewController, UITextFieldDelegate {

    @IBOutlet var advertiseSwitch: UISwitch!
    @IBOutlet var advertiseLabel: UILabel!
    @IBOutlet var nameTextField: UITextField!
    @IBOutlet var uuidTextField: UITextField!
    @IBOutlet var majorTextField: UITextField!
    @IBOutlet var minorTextField: UITextField!
    @IBOutlet var generaUUIDBuuton: UIButton!

    required init?(coder aDecoder:NSCoder) {
        super.init(coder:aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.nameTextField.text = PeripheralStore.getBeaconName()
        self.uuidTextField.text = PeripheralStore.getBeaconUUID()?.uuidString
        let beaconMinorMajor = PeripheralStore.getBeaconMinorMajor()
        if beaconMinorMajor.count == 2 {
            self.minorTextField.text = "\(beaconMinorMajor[0])"
            self.majorTextField.text = "\(beaconMinorMajor[1])"
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setUIState()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }

    @IBAction func generateUUID(_ sender: AnyObject) {
        self.uuidTextField.text = UUID().uuidString
    }
        
    // UITextFieldDelegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        if let enteredUUID = self.uuidTextField.text, !enteredUUID.isEmpty {
            if let uuid = UUID(uuidString:enteredUUID) {
                PeripheralStore.setBeaconUUID(uuid)
            } else {
                self.present(UIAlertController.alertOnErrorWithMessage("UUID '\(enteredUUID)' is invalid."), animated:true, completion:nil)
                return false
            }
        }
        if let enteredName = self.nameTextField.text, !enteredName.isEmpty {
            PeripheralStore.setBeaconName(enteredName)
        }
        if let enteredMinor = self.minorTextField.text, let enteredMajor = self.majorTextField.text, !enteredMinor.isEmpty, !enteredMajor.isEmpty {
            if let minor = UInt16(enteredMinor), let major = UInt16(enteredMajor), minor <= 65535, major <= 65535 {
                PeripheralStore.setBeaconMinorMajor([minor, major])
            } else {
                self.present(UIAlertController.alertOnErrorWithMessage("major or minor not convertable to a number."), animated:true, completion:nil)
                return false
            }
        }
        setUIState()
        return true
    }

    @IBAction func toggleAdvertise(_ sender:AnyObject) {
        if Singletons.peripheralManager.isAdvertising {
            let stopAdvertisingFuture = Singletons.peripheralManager.stopAdvertising()
            stopAdvertisingFuture.onSuccess { [weak self] in
                self?.setUIState()
            }
            stopAdvertisingFuture.onFailure { [weak self] _ in
                self?.present(UIAlertController.alert(message: "Failed to stop advertising."), animated: true)
            }
            return
        }
        let beaconMinorMajor = PeripheralStore.getBeaconMinorMajor()
        if let uuid = PeripheralStore.getBeaconUUID(), let name = PeripheralStore.getBeaconName(), beaconMinorMajor.count == 2 {
            let beaconRegion = BeaconRegion(proximityUUID: uuid, identifier: name, major: beaconMinorMajor[1], minor: beaconMinorMajor[0])
            let startAdvertiseFuture = Singletons.peripheralManager.whenStateChanges().flatMap { state -> Future<Void> in
                switch state {
                case .poweredOn:
                    return Singletons.peripheralManager.startAdvertising(beaconRegion)
                case .poweredOff:
                    throw AppError.poweredOff
                case .unauthorized:
                    throw AppError.unauthorized
                case .unknown:
                    throw AppError.unknown
                case .unsupported:
                    throw AppError.unsupported
                case .resetting:
                    throw AppError.resetting
                }
            }

            startAdvertiseFuture.onSuccess { [weak self] in
                self?.setUIState()
                self?.present(UIAlertController.alert(message: "Powered on and started advertising."), animated: true, completion: nil)
            }

            startAdvertiseFuture.onFailure { [weak self] error in
                switch error {
                case AppError.poweredOff:
                    self?.present(UIAlertController.alert(message: "PeripheralManager powered off.") { _ in
                        Singletons.peripheralManager.reset()
                    }, animated: true)
                case AppError.resetting:
                    let message = "PeripheralManager state \"\(Singletons.peripheralManager.state)\". The connection with the system bluetooth service was momentarily lost.\n Restart advertising."
                    self?.present(UIAlertController.alert(message: message) { _ in
                        Singletons.peripheralManager.reset()
                    }, animated: true)
                case AppError.unsupported:
                    self?.present(UIAlertController.alert(message: "Bluetooth not supported."), animated: true)
                case AppError.unknown:
                    break
                default:
                    self?.present(UIAlertController.alert(error: error) { _ in
                        Singletons.peripheralManager.reset()
                    }, animated: true, completion: nil)
                }
                self?.setUIState()
                _ = Singletons.peripheralManager.stopAdvertising()
            }
        } else {
            present(UIAlertController.alert(message: "iBeacon config is invalid."), animated: true, completion: nil)
        }
    }

    func setUIState() {
        if Singletons.peripheralManager.isAdvertising {
            navigationItem.setHidesBackButton(true, animated:true)
            advertiseSwitch.isOn = true
            nameTextField.isEnabled = false
            uuidTextField.isEnabled = false
            majorTextField.isEnabled = false
            minorTextField.isEnabled = false
            generaUUIDBuuton.isEnabled = false
            advertiseLabel.textColor = UIColor.black
        } else {
            navigationItem.setHidesBackButton(false, animated:true)
            nameTextField.isEnabled = true
            uuidTextField.isEnabled = true
            majorTextField.isEnabled = true
            minorTextField.isEnabled = true
            generaUUIDBuuton.isEnabled = true
            if canAdvertise() {
                advertiseSwitch.isEnabled = true
                advertiseLabel.textColor = UIColor.black
            } else {
                advertiseSwitch.isEnabled = false
                advertiseLabel.textColor = UIColor.lightGray
            }
        }
    }

    func canAdvertise() -> Bool {
        return PeripheralStore.getBeaconUUID() != nil && PeripheralStore.getBeaconName() != nil && PeripheralStore.getBeaconMinorMajor().count == 2
    }
}
