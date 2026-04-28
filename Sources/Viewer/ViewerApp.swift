//
//  ViewerApp.swift
//  Markdown Eye
//
//  Created by Anton Leuski on 4/27/26.
//

import SwiftUI

@main
struct ViewerApp: App {
  var body: some Scene {
    DocumentGroup(newDocument: ViewerDocument()) { file in
      ContentView(document: file.$document)
    }
  }
}
