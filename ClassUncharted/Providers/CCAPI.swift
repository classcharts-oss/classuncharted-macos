//
//  API.swift
//  ClassUncharted
//
//  Created by Bradlee Barnes on 28/10/2024.
//

import Foundation

class CCAPI : APIProvider {
    func getDetentions() -> [Detention] {
        return [Detention()]
    }
    
    func getAnnouncements() -> [Announcement] {
        return [Announcement()]
    }
}
