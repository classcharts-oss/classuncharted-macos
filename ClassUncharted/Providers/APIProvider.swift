//
//  API.swift
//  ClassUncharted
//
//  Created by Bradlee Barnes on 28/10/2024.
//

import Foundation
import SwiftUI

protocol APIProvider: ObservableObject {
    func getAnnouncements() async throws -> AnnouncementResponse
}
