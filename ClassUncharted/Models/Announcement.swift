//
//  Announcement.swift
//  ClassUncharted
//
//  Created by Bradlee Barnes on 28/10/2024.
//

import Foundation

struct Announcement: Codable {
    var id: Int
    var title: String
    var description: String
}

typealias AnnouncementResponse = ClientResponse<[Announcement], AnyCodableValue>
