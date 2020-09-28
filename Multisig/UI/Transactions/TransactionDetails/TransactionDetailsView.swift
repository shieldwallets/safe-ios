//
//  TransactionDetailsView.swift
//  Multisig
//
//  Created by Moaaz on 5/29/20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import SwiftUI

struct TransactionDetailsView: View {
    @FetchRequest(fetchRequest: AppSettings.fetchRequest().all())
    private var appSettings: FetchedResults<AppSettings>

    @FetchRequest(fetchRequest: Safe.fetchRequest().selected())
    private var selectedSafe: FetchedResults<Safe>

    private var safe: Safe { selectedSafe.first! }

    private var canSign: Bool {
        model.transactionDetails.status == .awaitingConfirmations &&
            signingKeyAddress != nil &&
            model.transactionDetails.signers!.contains(signingKeyAddress!) &&
            !model.transactionDetails.confirmations!.map { $0.address }.contains(signingKeyAddress!)
    }

    @ObservedObject
    var model: TransactionDetailsViewModel

    init(transaction: TransactionViewModel) {
        model = TransactionDetailsViewModel(transaction: transaction)
    }

    private var signingKeyAddress: String? {
        return appSettings.first?.signingKeyAddress
    }

    var body: some View {
        ZStack {
            LoadableView(TransactionDetailsBodyView(model: model, safe: safe), reloadsOnAppOpen: false)

            if App.configuration.toggles.signing && canSign {
                confirmButtonView
            }
        }
        .navigationBarTitle("Transaction Details", displayMode: .inline)
        .background(Color.gnoWhite)
        .onAppear {
            self.trackEvent(.transactionsDetails)
        }
    }

    private var confirmButtonView: some View {
        VStack {
            Spacer()

            Button(action: {
                self.confirmTransaction()
            }) {
                Text("Confirm")
            }
            .buttonStyle(GNOFilledButtonStyle())
            .padding()
        }
    }

    private func confirmTransaction() {
        print("Confirm")
    }
}


fileprivate struct TransactionDetailsBodyView: Loadable {
    let model: TransactionDetailsViewModel
    let safe: Safe

    private var transactionDetails: TransactionViewModel {
        model.transactionDetails
    }

    @State
    private var showsLink: Bool = false
    private let padding: CGFloat = 11

    var body: some View {
        List {
            if transactionDetails is CreationTransactionViewModel {
                CreationTransactionBodyView(transaction: transactionDetails as! CreationTransactionViewModel)
            } else {
                detailsBodyView
            }
            
            if transactionDetails.browserURL != nil {
                viewTxOnEtherscan
            }
        }
        .navigationBarTitle("Transaction Details", displayMode: .inline)
        .onAppear {
            self.trackEvent(.transactionsDetails)
        }
    }

    var detailsBodyView: some View {
        Group {
            TransactionHeaderView(transaction: transactionDetails)

            if dataDecoded != nil {
                TransactionActionView(dataDecoded: dataDecoded!)
            }

            if data != nil {
                VStack (alignment: .leading) {
                    Text("Data").headline()
                    ExpandableButton(title: "\(data!.length) Bytes", value: data!.data)
                }.padding(.vertical, padding)
            }

            TransactionStatusTypeView(transaction: transactionDetails)
            if displayConfirmations {
                TransactionConfirmationsView(transaction: transactionDetails, safe: safe).padding(.vertical, padding)
            }

            if transactionDetails.formattedCreatedDate != nil {
                KeyValueRow("Created:",
                            value: transactionDetails.formattedCreatedDate!,
                            enableCopy: false,
                            color: .gnoDarkGrey).padding(.vertical, padding)
            }

            if transactionDetails.formattedExecutedDate != nil {
                KeyValueRow("Executed:",
                            value: transactionDetails.formattedExecutedDate!,
                            enableCopy: false,
                            color: .gnoDarkGrey).padding(.vertical, padding)
            }

            if transactionDetails.hasAdvancedDetails {
                NavigationLink(destination: AdvancedTransactionDetailsView(transaction: transactionDetails)) {
                    Text("Advanced").body()
                }
                .frame(height: 48)
            }
        }
    }

    private var viewTxOnEtherscan: some View {
        Button(action: { self.showsLink.toggle() }) {
            LinkText(title: "View transaction on Etherscan")
        }
        .buttonStyle(BorderlessButtonStyle())
        .foregroundColor(.gnoHold)
        .sheet(isPresented: $showsLink, content: browseTransaction)
        .padding(.vertical, padding)
    }


    private func browseTransaction() -> some View {
        SafariViewController(url: transactionDetails.browserURL!)
    }

    private var data: (length: UInt256, data: String)? {
        guard let customTransaction = transactionDetails as? CustomTransactionViewModel,
              let data = customTransaction.data else {
            return nil
        }

        return (length: customTransaction.dataLength, data: data)
    }

    private var dataDecoded: DataDecoded? {
        guard let customTransaction = transactionDetails as? CustomTransactionViewModel else {
            return nil
        }

        return customTransaction.dataDecoded
    }

    private var displayConfirmations: Bool {
        guard let transferTransaction = transactionDetails as? TransferTransactionViewModel else {
            return true
        }

        return transferTransaction.isOutgoing
    }
}
