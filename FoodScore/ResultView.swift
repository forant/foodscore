//
//  ResultView.swift
//  FoodScore
//
//  Created by Timothy Foran on 3/31/26.
//

import SwiftUI

struct ResultView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Big score display
                Text("7 / 10")
                    .font(.system(size: 64, weight: .bold))
                    .padding(.top)

                // What helps section
                VStack(alignment: .leading, spacing: 8) {
                    Label("What helps", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)

                    Text("• High in dietary fiber")
                    Text("• Low in saturated fat")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // What hurts section
                VStack(alignment: .leading, spacing: 8) {
                    Label("What hurts", systemImage: "xmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)

                    Text("• High in added sugars")
                    Text("• High in sodium")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Disclaimer
                Text("General nutrition guidance only, not medical advice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top)
            }
            .padding()
        }
        .navigationTitle("Results")
    }
}

#Preview {
    NavigationStack {
        ResultView()
    }
}
