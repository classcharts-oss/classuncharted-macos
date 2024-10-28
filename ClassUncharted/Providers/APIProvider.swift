//
//  API.swift
//  ClassUncharted
//
//  Created by Bradlee Barnes on 28/10/2024.
//

import Foundation

protocol APIProvider {
    func getDetentions() -> [Detention]
    func getAnnouncements() -> [Announcement]
}
