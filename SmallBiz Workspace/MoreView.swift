import SwiftUI

struct MoreView: View {
    var body: some View {
        List {
            NavigationLink {
                PortalPreviewView()
            } label: {
                Label("Portal Preview", systemImage: "person.crop.rectangle")
            }
           
                      
            NavigationLink {
                JobsListView()
            } label: {
                Label("Requests", systemImage: "tray.full")
            }

            NavigationLink {
                FilesHomeView()
            } label: {
                Label("Files", systemImage: "folder")
            }

            NavigationLink {
                ContractsHomeView()
            } label: {
                Label("Contracts", systemImage: "doc.text")
            }
            
            NavigationLink {
                ClientListView()
            } label: {
                Label("Clients", systemImage: "person.2")
            }
            
            NavigationLink {
                EstimateListView()
            } label: {
                Label("Estimates", systemImage: "doc.text.fill")
            }
            
            NavigationLink {
                InvoiceListView()
            } label: {
                Label("Invoices", systemImage: "doc.text.fill")
            }
        }
        .navigationTitle("More")
    }
}
