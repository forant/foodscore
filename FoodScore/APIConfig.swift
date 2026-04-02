//
//  APIConfig.swift
//  FoodScore
//
//  Single place to define the backend URL.
//  DEBUG builds (Simulator / Xcode Run) → localhost
//  RELEASE builds (Archive / TestFlight) → Render
//

import Foundation

enum APIConfig {
    #if DEBUG
    static let baseURL = "http://127.0.0.1:8000"
    #else
    static let baseURL = "https://foodscore-backend.onrender.com"
    #endif
}
