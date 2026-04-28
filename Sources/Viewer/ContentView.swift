//
//  ContentView.swift
//  Markdown Eye
//
//  Created by Anton Leuski on 4/27/26.
//

import SwiftUI

struct ContentView: View {
  @Binding var document: ViewerDocument

  var body: some View {
    TextEditor(text: $document.text)
  }
}

#Preview {
  ContentView(document: .constant(ViewerDocument()))
}
