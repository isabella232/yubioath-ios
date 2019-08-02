//
//  Credential.swift
//  Authenticator
//
//  Created by Irina Makhalova on 7/26/19.
//  Copyright © 2019 Irina Makhalova. All rights reserved.
//

import Foundation

protocol CredentialExpirationDelegate: NSObjectProtocol {
    func calculateResultDidExpire(_ credential: Credential)
}

class Credential: NSObject {
    /*!
     The credential type (HOTP or TOTP).
     */
    let type: YKFOATHCredentialType;
    
    /*!
     The Issuer of the credential as defined in the Key URI Format specifications:
     https://github.com/google/google-authenticator/wiki/Key-Uri-Format
     */
    let issuer: String;
    
    /*!
     The validity period for a TOTP code, in seconds. The default value for this property is 30.
     If the credential is of HOTP type, this property returns 0.
     */
    let period: UInt;
    
    /*!
     The account name extracted from the label. If the label does not contain the issuer, the
     name is the same as the label.
     */
    let account: String;
    
    let validity : DateInterval
    let code: String
    
    weak var delegate: CredentialExpirationDelegate?
    private var timerObservation: NSKeyValueObservation?
    @objc dynamic private var globalTimer = GlobalTimer.shared

    init(fromYKFOATHCredential credential:YKFOATHCredential, otp: String, valid: DateInterval) {
        type = credential.type
        account = credential.account
        issuer = credential.issuer
        period = credential.period
        code = otp
        validity = valid

        super.init()
        if (type == .TOTP && !code.isEmpty) {
            // set up timer to get notified about expiration (by watching global timer changes)
            self.setupTimerObservation()
        }
    }
    
    init(fromYKFOATHCredentialCalculateResult credential:YKFOATHCredentialCalculateResult) {
        type = credential.type
        account = credential.account
        issuer = credential.issuer ?? ""
        period = credential.period
        
        code = credential.otp ?? ""
        validity = credential.validity
        
        super.init()
        if (type == .TOTP && !code.isEmpty) {
            self.setupTimerObservation()
        }
    }
    
    var uniqueId: String {
        get {
            if (type == YKFOATHCredentialType.TOTP) {
                return String(format:"%d/%@:%@", period, issuer, account);
            } else {
                return String(format:"%@:%@", issuer, account);
            }
        }
    }
    
    var ykCredential : YKFOATHCredential {
        let credential = YKFOATHCredential()
        credential.account = account
        credential.type = type
        credential.issuer = issuer
        credential.period = period
        credential.label = "\(credential.issuer):\(credential.account)"
        credential.label = String(format:"%@:%@", issuer, account)
        return credential
    }
    
    // MARK: - NSObjectProtocol for using within Set
    static func == (lhs: Credential, rhs: Credential) -> Bool {
        return lhs.uniqueId == rhs.uniqueId
    }
    
    override func isEqual(_ object: Any?) -> Bool {
        if let rhs = object as? Credential {
            return self == rhs
        }
        return false
        
    }
    override public var hash: Int { return uniqueId.hashValue }
    
    
    // MARK: - Observation
    
    func setupTimerObservation() {
        timerObservation = observe(\.globalTimer.tick, options: [], changeHandler: { [weak self] (object, change) in
            guard let self = self else {
                return
            }
            if (self.timerObservation == nil) {
                // timer should
                return
            }
            let remainingTime = self.validity.end.timeIntervalSince(Date())
            if remainingTime <= 0 {
                self.delegate?.calculateResultDidExpire(self)
                self.removeTimerObservation()
            }
        })
    }
    
    func removeTimerObservation() {
        timerObservation = nil
    }
}
