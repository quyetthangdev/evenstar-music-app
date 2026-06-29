//
//  EvenstarApp.swift
//  Evenstar
//
//  Created by Phan Quyết Thắng on 29/6/26.
//

import SwiftUI

  @main
  struct EvenstarApp: App {
      var body: some Scene {
          WindowGroup {
              VStack(spacing: 16) {
                  Image(systemName: "music.note")
                      .font(.system(size: 72))
                      .foregroundStyle(.tint)
                  Text("Hello, Evenstar")
                      .font(.largeTitle)
                      .bold()
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(Color(.systemGroupedBackground))
          }
      }
  }
