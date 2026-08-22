//
//  UnreadCountBadge.swift
//  SpectRoom
//

import SwiftUI

struct UnreadCountBadge: View {
    let count: Int
    
    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.white)
                .padding(3)
                .frame(minWidth: 16, minHeight: 16)
                .background(Color.red)
                .clipShape(Circle())
        }
    }
}
