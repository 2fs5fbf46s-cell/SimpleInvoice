//
//  Binding+ZeroAsEmpty.swift
//  SmallBiz Workspace
//

import SwiftUI

extension Binding where Value == Double {
    /// For a number field: zero shows as an empty field (so its placeholder
    /// shows) instead of "0.00". A field that starts at "$0.00" puts the cursor
    /// in front of the zeros, so typing 325 made the price $3,250.
    var zeroAsEmpty: Binding<Double?> {
        Binding<Double?>(
            get: { wrappedValue == 0 ? nil : wrappedValue },
            set: { wrappedValue = $0 ?? 0 }
        )
    }
}
