//
//  MainViewController.swift
//  Authenticator
//
//  Created by Irina Makhalova on 7/18/19.
//  Copyright © 2019 Irina Makhalova. All rights reserved.
//

import UIKit

class MainViewController: BaseOATHVIewController {

    private var credentialsSearchController: UISearchController!
    private var keySessionObserver: KeySessionObserver!
    
    private var credentailToAdd: YKFOATHCredential?

    override func viewDidLoad() {
        super.viewDidLoad()

        setupCredentialsSearchController()
        
        if (!YubiKitDeviceCapabilities.supportsMFIAccessoryKey) {
            let error = KeySessionError.notSupported
            self.showAlertDialog(title: "", message: error.localizedDescription)
        }

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        keySessionObserver = KeySessionObserver(delegate: self)
        refreshUIOnKeyStateUpdate()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        keySessionObserver.observeSessionState = false
        super.viewWillDisappear(animated)
    }
    
    //
    // MARK: - Add cedential
    //
    @IBAction func onAddCredentialClick(_ sender: Any) {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        if (YubiKitDeviceCapabilities.supportsQRCodeScanning) {
            // if QR codes are anavailable on device disable option
            actionSheet.addAction(UIAlertAction(title: "Scan QR code", style: .default) { [weak self]  (action) in
                self?.scanQR()
            })
        }
        actionSheet.addAction(UIAlertAction(title: "Enter manually", style: .default) { [weak self]  (action) in
            self?.performSegue(withIdentifier: .addCredentialSequeID, sender: self)
        })
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] (action) in
            self?.dismiss(animated: true, completion: nil)
        })
        
        // The action sheet requires a presentation popover on iPad.
        if UIDevice.current.userInterfaceIdiom == .pad {
            actionSheet.modalPresentationStyle = .popover
            actionSheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?[1]
        }
        
        present(actionSheet, animated: true, completion: nil)
    }
    
    //
    // MARK: - Table view data source
    //
    override func numberOfSections(in tableView: UITableView) -> Int {
        if (viewModel.credentials.count > 0) {
            self.tableView.backgroundView = nil
            self.tableView.separatorStyle = .singleLine
            return 1
        } else {
            // Display a message when the table is empty
            let messageLabel = UILabel(frame: CGRect(x: 0, y: 0, width: self.view.bounds.size.width - 20, height: self.view.bounds.size.height - 20))
            messageLabel.textAlignment = NSTextAlignment.center
            messageLabel.numberOfLines = 5
            
            switch viewModel.state {
            case .idle:
                messageLabel.text = "Insert your YubiKey"
            case .loading:
                messageLabel.text = "Loading..."
            case .locked:
                messageLabel.text = "Authentication is required"
            default:
                messageLabel.text = "No credentials.\nAdd credential to this YubiKey in order to be able to generate security codes from it."
            }
            
            messageLabel.center = self.view.center
            messageLabel.sizeToFit()
            
            self.tableView.backgroundView = messageLabel;
            self.tableView.separatorStyle = .none
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.credentials.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CredentialCell", for: indexPath) as! CredentialTableViewCell
        let credential = viewModel.credentials[indexPath.row]
        cell.updateView(credential: credential)
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            let credential = viewModel.credentials[indexPath.row]
            if (credential.type == .HOTP && credential.activeTime > 5) {
                // refresh HOTP on touch
                print("HOTP active for \(String(format:"%f", credential.activeTime)) seconds")
                viewModel.calculate(credential: credential)
            } else if (credential.code.isEmpty || credential.remainingTime <= 0) {
                // refresh items that require touch
                viewModel.calculate(credential: credential)
            } else {
                // copy to clipbboard
                UIPasteboard.general.string = credential.code
                self.displayToast(message: "Copied to clipboard!")
            }
        }
    }

    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            viewModel.deleteCredential(index: indexPath.row)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    
    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == .addCredentialSequeID {
            let destinationNavigationController = segue.destination as! UINavigationController
            if let addViewController = destinationNavigationController.topViewController as? AddCredentialController, let credential = credentailToAdd {
                    addViewController.displayCredential(details: credential)
                }
            credentailToAdd = nil
        }
    }
    
    @IBAction func unwindToMainViewController(segue: UIStoryboardSegue) {
        if let sourceViewController = segue.source as? AddCredentialController, let credential = sourceViewController.credential {
            // Add a new credential to table.
            viewModel.addCredential(credential: credential)
        }
    }
    
    // MARK: - private methods
    
    private func scanQR() {
        YubiKitManager.shared.qrReaderSession.scanQrCode(withPresenter: self) {
            [weak self] (payload, error) in
            guard self != nil else {
                return
            }
            guard error == nil else {
                self?.onError(operation: .scan, error: error!)
                return
            }
            
            // This is an URL conforming to Key URI Format specs.
            guard let url = URL(string: payload!) else {
                self?.onError(operation: .scan, error: KeySessionError.invalidUri)
                return
            }
            
            guard let credential = YKFOATHCredential(url: url) else {
                self?.onError(operation: .scan, error: KeySessionError.invalidCredentialUri)
                return
            }
            
            self?.credentailToAdd = credential
            self?.performSegue(withIdentifier: .addCredentialSequeID, sender: self)
        }
    }

    private func refreshCredentials() {
        if (YubiKitDeviceCapabilities.supportsMFIAccessoryKey) {
            let sessionState = YubiKitManager.shared.keySession.sessionState
            print("Key session state: \(String(describing: sessionState.rawValue))")
            
            if (sessionState == YKFKeySessionState.open) {
                viewModel.calculateAll()
                tableView.reloadData()
            } else {
                // if YubiKey is unplugged do not show any OTP codes
                viewModel.cleanUp()
            }
        } else {
#if DEBUG
            // show some credentials on emulator
            viewModel.emulateSomeRecords()
#endif
        }
    }
    
    
    //
    // MARK: - UI Setup
    //
    private func setupCredentialsSearchController() {
        credentialsSearchController = UISearchController(searchResultsController: nil)
        credentialsSearchController.searchResultsUpdater = self
        credentialsSearchController.obscuresBackgroundDuringPresentation = false
        credentialsSearchController.dimsBackgroundDuringPresentation = false
        credentialsSearchController.searchBar.placeholder = "Quick Find"
        navigationItem.searchController = credentialsSearchController
        navigationItem.hidesSearchBarWhenScrolling = true
        definesPresentationContext = true
    }

    private func refreshUIOnKeyStateUpdate() {
        #if DEBUG
            // allow to see add option on emulator
            navigationItem.rightBarButtonItems?[1].isEnabled = YubiKitManager.shared.keySession.isKeyConnected || !YubiKitDeviceCapabilities.supportsMFIAccessoryKey
        #else
            navigationItem.rightBarButtonItems?[1].isEnabled = YubiKitManager.shared.keySession.isKeyConnected
        #endif
        
        view.setNeedsLayout()
        refreshCredentials()
    }

    //
    // MARK: - CredentialViewModelDelegate
    //
    override func onOperationCompleted(operation: OperationName) {
        switch operation {
        case .calculate:
            break
        case .filter:
            self.tableView.reloadData()
        default:
            // show search bar only if there are credentials on the key
            navigationItem.searchController = viewModel.credentials.count > 0 ? credentialsSearchController : nil
            self.tableView.reloadData()
        }
    }

}

extension String {
    fileprivate static let addCredentialSequeID = "AddCredentialSequeID"
}

//
// MARK: - Key Session Observer
//
extension  MainViewController: KeySessionObserverDelegate {
    
    func keySessionObserver(_ observer: KeySessionObserver, sessionStateChangedTo state: YKFKeySessionState) {
        refreshUIOnKeyStateUpdate()
    }
}

//
// MARK: - Search Results Extension
//

extension MainViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let filter = searchController.searchBar.text
        viewModel.applyFilter(filter: filter)
    }
}
    
