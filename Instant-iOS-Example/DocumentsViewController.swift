//
//  Copyright © 2017-2025 PSPDFKit GmbH. All rights reserved.
//
//  The Nutrient Sample applications are licensed with a modified BSD license.
//  Please see License for details. This notice may not be removed from this file.
//

import UIKit
import Instant
extension APIClient.Layer {
    init(descriptor: InstantDocumentDescriptor) {
        self.init(documentID: descriptor.identifier, name: descriptor.layerName)
    }
}

class DocumentsViewController: UITableViewController, InstantClientDelegate {
    private let cellReuseIdentifier = "cell"
    private typealias Layer = APIClient.Layer

    struct RowData {
        var title: String {
            if documentDescriptor.layerName.isEmpty {
                return "<Default Layer>"
            } else {
                return documentDescriptor.layerName
            }
        }
        let documentDescriptor: InstantDocumentDescriptor
        let JWT: String?
    }

    struct SectionData {
        let title: String
        var rows: [RowData]
    }

    /// The array used in the table view data source methods.
    private var listData: [SectionData] = [] {
        didSet {
            precondition(Thread.isMainThread)
            guard isViewLoaded else {
                return
            }
            tableView.reloadData()
        }
    }

    private var documentListFetchTask: URLSessionTask?

    /// Used to keep track of the last document shown in a view controller, so we can pop it if the document is removed remotely.
    private var lastShownDescriptor: InstantDocumentDescriptor?

    /// Client for the Nutrient Document Engine.
    let instantClient: InstantClient

    /// Client for the example server, as a stand-in for your own backend.
    let apiClient: APIClient

    init(instantClient: InstantClient, apiClient: APIClient) {
        self.instantClient = instantClient
        self.apiClient = apiClient

        super.init(style: .plain)

        instantClient.delegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)

        let refresher = UIRefreshControl()
        refresher.attributedTitle = NSAttributedString(string: "Refresh Available Documents")
        refresher.addTarget(self, action: #selector(reloadList(_:)), for: .valueChanged)
        refreshControl = refresher
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(clearLocalStorage(_:)))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if listData.isEmpty {
            reloadList(refreshControl)
        }
    }

    @objc func reloadList(_ sender: Any?) {
        let refresher = refreshControl
        if let refresher, refresher.isRefreshing == false {
            refresher.beginRefreshing()
        }

        lastShownDescriptor = nil
        /*
         When programmatically refreshing, and running in the simulator, the response will come so
         quickly that we won’t even see the refresh animation at all.
         To ensure a smooth animation, we schedule the callback that stops the refresh control and
         updates the list at least 0.7 second in the future.
         */
        let earliestUpdate = DispatchTime.now() + .milliseconds(700)
        let task = apiClient.fetchDocumentListTask { result in
            switch result {
            case .failure(let reason):
                print("Could not fetch document list: \(reason)")
                DispatchQueue.main.asyncAfter(deadline: earliestUpdate) {
                    refresher?.endRefreshing()
                }
            case .success(let apiClientDocuments):
                if apiClientDocuments.isEmpty {
                    print("No documents found. Upload one at \(self.apiClient.baseURL)")
                }

                let newListData = apiClientDocuments.compactMap { document -> SectionData? in
                    let layers = document.JWTs.compactMap { JWT -> RowData? in
                        do {
                            let documentDescriptor = try self.instantClient.documentDescriptor(forJWT: JWT)
                            return RowData(documentDescriptor: documentDescriptor, JWT: JWT)
                        } catch {
                            print("Could not make document descriptor from JWT '\(JWT)': \(error)")
                            return nil
                        }
                    }

                    if layers.isEmpty {
                        return nil
                    } else {
                        return SectionData(title: document.title, rows: layers)
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: earliestUpdate) {
                    self.listData = newListData
                    refresher?.endRefreshing()
                }
            }
        }

        documentListFetchTask?.cancel()
        documentListFetchTask = task
        task.resume()
    }

    @IBAction func clearLocalStorage(_ sender: Any?) {
        try! instantClient.removeLocalStorage()

        // Removing the local storage invalidates the document descriptors => replace all of them
        lastShownDescriptor = nil
        reloadList(nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        documentListFetchTask?.cancel()
        documentListFetchTask = nil
    }

    // MARK: - UITableViewDataSource
    override func numberOfSections(in tableView: UITableView) -> Int {
        return listData.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return listData[section].rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return listData[section].title
    }

    private func row(at indexPath: IndexPath) -> RowData {
        return listData[indexPath.section].rows[indexPath.row]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let rowData = row(at: indexPath)
        var text = rowData.title

        // For demonstration, add a cloud if the document has not been downloaded.
        if rowData.documentDescriptor.isDownloaded == false {
            text += " ☁️"
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath)
        cell.textLabel!.text = text

        return cell
    }

    // MARK: - Activity Tracking

    private var layersBeingDownloaded: Set<Layer> = []
    private var layersBeingAuthenticated: Set<Layer> = []
    private func isInFlight(layer: Layer) -> Bool {
        return layersBeingDownloaded.contains(layer) || layersBeingAuthenticated.contains(layer)
    }
    private func startDownloadIfNeeded(for descriptor: InstantDocumentDescriptor, withJWT JWT: String?, identifiedBy layer: Layer) {
        guard
            !descriptor.isDownloaded,
            !isInFlight(layer: layer)
        else { return }

        let startDownloadWithJWT = { (JWT: String) -> Void in
            do {
                try descriptor.download(usingJWT: JWT)
                self.layersBeingDownloaded.insert(layer)
            } catch {
                print("Could not start downloading layer '\(layer)': \(error)")
            }
        }

        if let JWT {
            startDownloadWithJWT(JWT)
        } else {
            layersBeingAuthenticated.insert(layer)
            apiClient.fetchAuthenticationTokenTask(for: layer, completionHandler: { result in
                DispatchQueue.main.async {
                    self.layersBeingAuthenticated.remove(layer)
                    switch result {
                    case .failure(let reason):
                        print("Could not fetch authentication token for layer ‘\(layer)’: \(reason)")
                    case .success(let JWT):
                        startDownloadWithJWT(JWT)
                    }
                }
            }).resume()
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let rowData = row(at: indexPath)
        let descriptor = rowData.documentDescriptor
        let layer = Layer(descriptor: descriptor)
        startDownloadIfNeeded(for: descriptor, withJWT: rowData.JWT, identifiedBy: layer)

        let pdfViewController = InstantViewController(document: descriptor.editableDocument)
        let deleteItem = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(removeDocumentStorage(_:)))
        let barItems = [pdfViewController.thumbnailsButtonItem, pdfViewController.annotationButtonItem, deleteItem]
        pdfViewController.navigationItem.setRightBarButtonItems(barItems, for: .document, animated: false)
        self.navigationController?.pushViewController(pdfViewController, animated: true)
        lastShownDescriptor = descriptor
    }

    // MARK: -

    @objc func removeDocumentStorage(_ sender: Any?) {
        guard
            let documentDescriptor = lastShownDescriptor
        else { return }

        do {
            try documentDescriptor.removeLocalStorage()
            let layer = Layer(descriptor: documentDescriptor)
            layersBeingAuthenticated.remove(layer)
            layersBeingDownloaded.remove(layer)
            tableView.reloadData()
        } catch {
            print(error)
        }
    }

    // MARK: - PSPDFInstantClientDelegate
    func instantClient(_ instantClient: InstantClient, didFinishDownloadFor documentDescriptor: InstantDocumentDescriptor) {
        DispatchQueue.main.async {
            self.layersBeingDownloaded.remove(Layer(descriptor: documentDescriptor))
            if let path = self.pathToRow(where: { $0 === documentDescriptor }) {
                self.tableView?.reloadRows(at: [path], with: .automatic)
            }
        }
    }

    private func pathToRow(where descriptorPredicate: (InstantDocumentDescriptor) -> Bool) -> IndexPath? {
        for section in listData.enumerated() {
            for row in section.element.rows.enumerated() {
                if descriptorPredicate(row.element.documentDescriptor) {
                    return IndexPath(row: row.offset, section: section.offset)
                }
            }
        }

        return nil
    }

    func instantClient(_ instantClient: InstantClient, documentDescriptor: InstantDocumentDescriptor, didFailDownloadWithError error: Error) {
        print("Failed to download document: \(error)")

        DispatchQueue.main.async {
            self.layersBeingDownloaded.remove(Layer(descriptor: documentDescriptor))
        }
    }

    func instantClient(_ instantClient: InstantClient, documentDescriptor: InstantDocumentDescriptor, didFailSyncWithError error: Error) {
        if case CocoaError.userCancelled = error {
            // We’re not really interested in cancellation: that error is only provided so you know when a sync ended
            return
        }
        print("Failed sync: \(error)")
    }

    private func replaceJWT(for descriptor: InstantDocumentDescriptor, with newValue: String?) {
        if let position = pathToRow(where: { $0 === descriptor }) {
            listData[position.section].rows[position.row] = RowData(documentDescriptor: descriptor, JWT: newValue)
        }
    }

    func instantClient(_ instantClient: InstantClient, didFailAuthenticationFor documentDescriptor: InstantDocumentDescriptor) {
        DispatchQueue.main.async {
            let layer = Layer(descriptor: documentDescriptor)
            guard
                self.layersBeingAuthenticated.insert(layer).inserted
            else { return }

            // Clear the current JWT so we don’t use it again and then start authentication
            self.replaceJWT(for: documentDescriptor, with: nil)
            self.apiClient.fetchAuthenticationTokenTask(for: layer, completionHandler: { result in
                DispatchQueue.main.async {
                    self.layersBeingAuthenticated.remove(layer)
                    switch result {
                    case .failure(let reason):
                        print("Could not fetch authentication token for layer ‘\(layer)’: \(reason)")
                        self.layersBeingDownloaded.remove(layer)
                    case .success(let JWT):
                        documentDescriptor.reauthenticate(withJWT: JWT)
                    }
                }
            }).resume()
        }
    }

    func instantClient(_ instantClient: InstantClient, documentDescriptor: InstantDocumentDescriptor, didFinishReauthenticationWithJWT validJWT: String) {
        DispatchQueue.main.async {
            self.layersBeingAuthenticated.remove(Layer(descriptor: documentDescriptor))
            self.replaceJWT(for: documentDescriptor, with: validJWT)
        }
    }

    func instantClient(_ instantClient: InstantClient, documentDescriptor: InstantDocumentDescriptor, didFailReauthenticationWithError error: Error) {
        DispatchQueue.main.async {
            let layer = Layer(descriptor: documentDescriptor)
            print("Could not update authentication token for layer '\(layer)': \(error)")
            self.layersBeingAuthenticated.remove(layer)
            self.layersBeingDownloaded.remove(layer)

            if case InstantError.accessDenied = error {
                // We’ve lost access to the document => purge its data from disk!
                try? documentDescriptor.removeLocalStorage()

                // Also, there’s no point of it being shown in the list anymore
                if let path = self.pathToRow(where: { $0.identifier == layer.documentID }) {
                    print("Removing the document from the list — hint: if you think you should still be able to access the document, refresh the list")
                    self.listData[path.section].rows.remove(at: path.row)
                }
            }
        }
    }
}
