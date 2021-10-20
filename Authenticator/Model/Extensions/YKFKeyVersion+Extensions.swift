//
//  YKFVersion+Extensions.swift
//  Authenticator
//
//  Created by Jens Utbult on 2020-05-14.
//  Copyright © 2020 Yubico. All rights reserved.
//

extension YKFVersion: Comparable {
    
    static public func ==(lhs: YKFVersion, rhs: YKFVersion) -> Bool {
        return lhs.major == lhs.major && lhs.minor == rhs.minor && lhs.micro == rhs.micro
    }
    
    static public func <(lhs: YKFVersion, rhs: YKFVersion) -> Bool {
        if (lhs.major != rhs.major) {
            return lhs.major < rhs.major
        } else if (lhs.minor != rhs.minor) {
            return lhs.minor < rhs.minor
        } else {
            return lhs.micro < rhs.micro
        }
    }
    
}
