//
//  OpenHomeSettingsView.swift
//
//
//  Created by GitHub Copilot on 25/10/2025.
//

import SwiftUI
import TipKit
import ConnectorProtocol
import SwiftMPD

public struct MPDSettingsView: View {
    @ObservedObject private var player: MPDPlayer
    @State private var customPlayerName: String = ""
    @State private var selectedType: MPDType = MPDType.allCases.first!
    @State private var isHidden: Bool
    @State private var useHTTPCoverArt: Bool

    // New state for advanced and output settings
    @State private var ipAddressField: String = ""
    @State private var connectToIp: Bool = false
    @State private var outputHostField: String = ""
    @State private var outputPortField: String = ""
    @State private var passwordField: String = ""
    @State private var appliedPassword: String = ""
    @State private var appliedIpAddress: String = ""
    @State private var appliedConnectToIp: Bool = false
    @FocusState private var passwordFieldFocused: Bool
    @FocusState private var ipAddressFieldFocused: Bool

    // Database status
    @State private var albumGroupingSelection: String = "albumartist"
    @State private var databaseStatusText: String = ""
    @State private var databaseArtists: String = "-"
    @State private var databaseAlbums: String = "-"
    @State private var databaseSongs: String = "-"
    @State private var performingDBAction: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    
    private let changeNameTip = MPDChangeNameTip()
    private let deleteAction: ((any PlayerProtocol) -> ())?
    private let hideAction: ((any PlayerProtocol) -> ())?

    public init(player: MPDPlayer, deleteAction: ((any PlayerProtocol) -> ())?, hideAction: ((any PlayerProtocol) -> ())?) {
        self.player = player
        self.deleteAction = deleteAction
        self.hideAction = hideAction
        
        // Initialize fields from userDefaults if available
        let ud = player.userDefaults
        let storedIpAddress = ud.string(forKey: MPDDefaultKey.ipAddress.stringValue(player)) ??  ""
        let storedConnectToIp = ud.bool(forKey: MPDDefaultKey.connectToIpAddress.stringValue(player))
        self._ipAddressField = State(initialValue: storedIpAddress)
        self._connectToIp = State(initialValue: storedConnectToIp)
        self._appliedIpAddress = State(initialValue: storedIpAddress)
        self._appliedConnectToIp = State(initialValue: storedConnectToIp)
        self._outputHostField = State(initialValue: ud.string(forKey: MPDDefaultKey.outputHost.stringValue(player)) ?? "")
        if let portVal = ud.object(forKey: MPDDefaultKey.outputPort.stringValue(player)) as? Int {
            self._outputPortField = State(initialValue: "\(portVal)")
        } else {
            self._outputPortField = State(initialValue: "")
        }
        let storedPassword = ud.string(forKey: MPDDefaultKey.password.stringValue(player)) ?? ""
        self._passwordField = State(initialValue: storedPassword)
        self._appliedPassword = State(initialValue: storedPassword)
        self._customPlayerName = State(initialValue: ud.string(forKey: MPDDefaultKey.customPlayerName.stringValue(player)) ?? "")
        self._isHidden = State(initialValue: ud.bool(forKey: MPDDefaultKey.hidden.stringValue(player)))
        self._useHTTPCoverArt = State(initialValue: ud.bool(forKey: MPDDefaultKey.useHttpCoverArt.stringValue(player)))

        // Initialize selected type from player
        self._selectedType = State(initialValue: player.type)
        
        self._albumGroupingSelection = State(initialValue: ud.string(forKey: MPDDefaultKey.albumGrouping.stringValue(player)) ??  "albumartist")
    }
    
    public var body: some View {
        Form {
            // Player Information Section
            Section(header: Text("Player Information", bundle: .module), footer: playerInformationFooter()) {
#if os(macOS)
                HStack {
                    Text("Type", bundle: .module)
                    Spacer()
                    Picker("Type", selection: $selectedType) {
                        ForEach(MPDType.selectableTypes, id: \.self) { t in
                            Text(String(describing: t)).tag(t)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedType) { _, newValue in
                        // Update player when type changes
                        player.type = newValue
                        player.userDefaults.set(newValue.rawValue, forKey: MPDDefaultKey.MPDType.stringValue(player))
                        player.objectWillChange.send()
                    }
                }
#else
                NavigationLink {
                    List {
                        ForEach(MPDType.selectableTypes, id: \.self) { t in
                            HStack {
                                Text(String(describing: t))
                                Spacer()
                                if t == selectedType { Image(systemName: "checkmark") }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedType = t
                                player.type = t
                                player.userDefaults.set(t.rawValue, forKey: MPDDefaultKey.MPDType.stringValue(player))
                                player.objectWillChange.send()
                            }
                        }
                    }
                    .navigationTitle(Text("Type", bundle: .module))
                } label: {
                    HStack {
                        Text("Type", bundle: .module)
                        Spacer()
                        Text(String(describing: selectedType))
                            .foregroundColor(.secondary)
                    }
                }
#endif
                
                HStack {
                    Text("Name", bundle: .module)
                    Spacer()
                    // Editable TextField; when empty the original player.name shows as prompt
                    TextField("", text: $customPlayerName, prompt: Text(player.name))
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.automatic)
                        .frame(maxWidth: 220)
                        .popoverTip(changeNameTip)
                        .onChange(of: customPlayerName) { _, newValue in
                            let key = MPDDefaultKey.customPlayerName.stringValue(player)
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty {
                                player.userDefaults.removeObject(forKey: key)
                                player.name = player.deviceName
                            } else {
                                player.userDefaults.set(trimmed, forKey: key)
                                player.name = trimmed
                            }
                            player.objectWillChange.send()
                        }
                }
                
                HStack {
                    Text("Version", bundle: .module)
                    Spacer()
                    Text(player.mpdConnector.version.description)
                        .foregroundColor(.secondary)
                }
                
                // Host and Port display
                HStack {
                    Text("Host", bundle: .module)
                    Spacer()
                    Text(player.attributes.host)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Port", bundle: .module)
                    Spacer()
                    Text(verbatim: "\(player.attributes.port)")
                        .foregroundColor(.secondary)
                }
                
                if player.attributes.manual {
                    HStack {
                        Text(String(localized: "Manually Added Player", bundle: .module))
                        Spacer()
                        if let deleteAction {
                            Button("Delete", role: .destructive) {
                                showDeleteConfirmation = true
                            }
                            .confirmationDialog(
                                Text("Are you sure you want to delete this player?", bundle: .module),
                                isPresented: $showDeleteConfirmation,
                                titleVisibility: .visible
                            ) {
                                Button(String(localized: "Delete", bundle: .module), role: .destructive) {
                                    deleteAction(player)
                                }
                                Button(String(localized: "Cancel", bundle: .module), role: .cancel) { }
                            }
                        }
                    }
                }
                else {
                    HStack {
                        Text(String(localized: "Hide Player", bundle: .module))
                        Spacer()
                        Toggle("", isOn: Binding<Bool>(
                            get: {
                                player.userDefaults.bool(forKey: MPDDefaultKey.hidden.stringValue(player))
                            },
                            set: { newValue in
                                player.userDefaults.set(newValue, forKey: MPDDefaultKey.hidden.stringValue(player))
                                if let hideAction {
                                    hideAction(player)
                                }
                            }
                        ))
                    }
                }
            }
            
            // Advanced Section
            Section(header: Text("Advanced", bundle: .module), footer: Text("If the player is not responding, you can connect directly to it's IP instead. Normally this shall be disabled.", bundle: .module)) {
                HStack {
                    Text(String(localized: "Use IP Address", bundle: .module))
                    Spacer()
                    Toggle("", isOn: $connectToIp)
                        .onChange(of: connectToIp) { _, _ in
                            updateIPAddressSettings()
                            commitConnectionSettingsIfNeeded()
                        }

                }

                HStack {
                    Text(String(localized: "IP Address to Use", bundle: .module))
                    Spacer()
                    TextField("", text: $ipAddressField)
                        .disabled(connectToIp == false)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.automatic)
                        .frame(maxWidth: 120)
                        .focused($ipAddressFieldFocused)
                        .onChange(of: ipAddressField) { _, _ in
                            updateIPAddressSettings()
                        }
                        .onChange(of: ipAddressFieldFocused) { _, isFocused in
                            if isFocused == false {
                                commitConnectionSettingsIfNeeded()
                            }
                        }
                        .onSubmit {
                            commitConnectionSettingsIfNeeded()
                        }
                }

                HStack {
                    Text(String(localized: "Password", bundle: .module))
                    Spacer()
                    SecureField("", text: $passwordField, prompt: Text(String(localized: "Password (optional)", bundle: .module)))
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.automatic)
                        .frame(maxWidth: 220)
                        .focused($passwordFieldFocused)
                        .onChange(of: passwordField) { _, _ in
                            updatePasswordSettings()
                        }
                        .onChange(of: passwordFieldFocused) { _, isFocused in
                            if isFocused == false {
                                commitConnectionSettingsIfNeeded()
                            }
                        }
                        .onSubmit {
                            commitConnectionSettingsIfNeeded()
                        }
                }

                if player.type == .moodeaudio || player.type == .bryston {
                    HStack {
                        Text(String(localized: "Use HTTP cover art", bundle: .module))
                        Spacer()
                        Toggle("", isOn: Binding<Bool>(
                            get: {
                                player.userDefaults.bool(forKey: MPDDefaultKey.useHttpCoverArt.stringValue(player))
                            },
                            set: { newValue in
                                player.userDefaults.set(newValue, forKey: MPDDefaultKey.useHttpCoverArt.stringValue(player))
                                player.attributes = MPDPlayer.PlayerAttributes(uuid: player.attributes.uuid,
                                                                               name: player.attributes.name,
                                                                               type: player.attributes.type,
                                                                               version: player.attributes.version,
                                                                               host: player.attributes.host,
                                                                               port: player.attributes.port,
                                                                               password: player.attributes.password,
                                                                               useHttpCoverArt: newValue,
                                                                               manual: player.attributes.manual,
                                                                               albumGrouping: player.attributes.albumGrouping,
                                                                               coverFilename: player.attributes.coverFilename,
                                                                               outputHost: player.attributes.outputHost,
                                                                               outputPort: player.attributes.outputPort)
                            }
                        ))
                    }
                }
                
                if player.type == .bryston, player.attributes.useHttpCoverArt == true {
                    HStack {
                        Text(String(localized: "Cover Filename", bundle: .module))
                        Spacer()
                        TextField("", text: Binding<String>(
                            get: {
                                player.userDefaults.string(forKey: MPDDefaultKey.coverPostfix.stringValue(player)) ?? ""
                            },
                            set: { newValue in
                                player.userDefaults.set(newValue, forKey: MPDDefaultKey.coverPostfix.stringValue(player))
                                player.attributes = MPDPlayer.PlayerAttributes(uuid: player.attributes.uuid,
                                                                               name: player.attributes.name,
                                                                               type: player.attributes.type,
                                                                               version: player.attributes.version,
                                                                               host: player.attributes.host,
                                                                               port: player.attributes.port,
                                                                               password: player.attributes.password,
                                                                               useHttpCoverArt: player.attributes.useHttpCoverArt,
                                                                               manual: player.attributes.manual,
                                                                               albumGrouping: player.attributes.albumGrouping,
                                                                               coverFilename: newValue,
                                                                               outputHost: player.attributes.outputHost,
                                                                               outputPort: player.attributes.outputPort)
                            }
                        ), prompt: Text("Enter cover art filename"))
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.automatic)
                            .onChange(of: outputHostField) { _, _ in
                                updateStreamSettings()
                            }
                    }
                }
            }
            
            // HTTP Output Section
            Section(header: Text("HTTP Stream", bundle: .module), footer: Text("If you have configured a http-stream output for mpd, you can enter the ip address and port number here. Rigelian can then play the stream on your local machine.", bundle: .module)) {
                HStack {
                    Text(String(localized: "Host or IP Address", bundle: .module))
                    Spacer()
                    TextField("", text: $outputHostField, prompt: Text("Enter hostname or IP"))
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.automatic)
                        .onChange(of: outputHostField) { _, _ in
                            updateStreamSettings()
                        }
                }
                HStack {
                    Text(String(localized: "Port number", bundle: .module))
                    Spacer()
                    let portFieldBinding = Binding(
                        get: { outputPortField },
                        set: { newValue in
                            let digitsOnly = newValue.filter { $0.isWholeNumber }
                            outputPortField = digitsOnly
                            updateStreamSettings()
                        }
                    )
                    TextField("", text: portFieldBinding, prompt: Text("Enter port"))
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.automatic)
#if os(iOS) || os(tvOS)
                        .keyboardType(.numberPad)
#endif
                }
            }
            
            // MPD Database Section
            Section(header: Text("MPD Database", bundle: .module)) {
                HStack {
                    Text("Status", bundle: .module)
                    Spacer()
                    Text(databaseStatusText)
                        .foregroundColor(.secondary)
                }
                
                if player.mpdConnector.version < MPDConnection.Version("0.20.0") {
                    HStack {
                        Text("Album Grouping", bundle: .module)
                        Spacer()
                        Picker("", selection: $albumGroupingSelection) {
                            Text("Album Artist", bundle: .module).tag("albumartist")
                            Text("Artist", bundle: .module).tag("artist")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: albumGroupingSelection) { _, newValue in
                            // Update player when type changes
                            player.userDefaults.set(newValue, forKey: MPDDefaultKey.albumGrouping.stringValue(player))
                            player.attributes = MPDPlayer.PlayerAttributes(uuid: player.attributes.uuid,
                                                                           name: player.attributes.name,
                                                                           type: player.attributes.type,
                                                                           version: player.attributes.version,
                                                                           host: player.attributes.host,
                                                                           port: player.attributes.port,
                                                                           password: player.attributes.password,
                                                                           useHttpCoverArt: player.attributes.useHttpCoverArt,
                                                                           manual: player.attributes.manual,
                                                                           albumGrouping: albumGroupingSelection,
                                                                           coverFilename: player.attributes.coverFilename,
                                                                           outputHost: player.attributes.outputHost,
                                                                           outputPort: player.attributes.outputPort)
                            player.objectWillChange.send()
                        }
                    }
                }
                
                HStack {
                    Text("Artists", bundle: .module)
                    Spacer()
                    Text(databaseArtists)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Albums", bundle: .module)
                    Spacer()
                    Text(databaseAlbums)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Songs", bundle: .module)
                    Spacer()
                    Text(databaseSongs)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 25){
                    Spacer()
                    
                    Button(String(localized: "Update Database", bundle: .module)) {
                        Task {
                            performingDBAction = true
                            do {
                                if let browse = player.browse as? MPDBrowse {
                                    _ = try await browse.updateDB()
                                    // refresh status and stats
                                    databaseStatusText = (try? await browse.databaseStatus()) ?? ""
                                    // try to fetch stats via status.stats()
                                    if let stats = try? await browse.databaseStats() {
                                        databaseArtists = "\(stats.artists)"
                                        databaseAlbums = "\(stats.albums)"
                                        databaseSongs = "\(stats.songs)"
                                    }
                                }
                            } catch {
                                databaseStatusText = "Error: \(error)"
                            }
                            performingDBAction = false
                        }
                    }
                    
                    Button(String(localized: "Rescan", bundle: .module), role: .destructive) {
                        Task {
                            performingDBAction = true
                            do {
                                if let browse = player.browse as? MPDBrowse {
                                    _ = try await browse.rescanLibrary()
                                    databaseStatusText = (try? await browse.databaseStatus()) ?? ""
                                    if let stats = try? await browse.databaseStats() {
                                        databaseArtists = "\(stats.artists)"
                                        databaseAlbums = "\(stats.albums)"
                                        databaseSongs = "\(stats.songs)"
                                    }
                                }
                            } catch {
                                databaseStatusText = "Error: \(error)"
                            }
                            performingDBAction = false
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .task {
            if let browse = player.browse as? MPDBrowse {
                databaseStatusText = (try? await browse.databaseStatus()) ?? ""
                if let stats = try? await browse.databaseStats() {
                    databaseArtists = "\(stats.artists)"
                    databaseAlbums = "\(stats.albums)"
                    databaseSongs = "\(stats.songs)"
                }
            }
        }
        .onChange(of: player.uniqueID) { _, _ in
            resetStateFromPlayer()
        }
        .onDisappear {
            commitConnectionSettingsIfNeeded()
        }
    }

    private func resetStateFromPlayer() {
        let ud = player.userDefaults
        selectedType = player.type
        let storedIpAddress = ud.string(forKey: MPDDefaultKey.ipAddress.stringValue(player)) ?? ""
        let storedConnectToIp = ud.bool(forKey: MPDDefaultKey.connectToIpAddress.stringValue(player))
        ipAddressField = storedIpAddress
        connectToIp = storedConnectToIp
        appliedIpAddress = storedIpAddress
        appliedConnectToIp = storedConnectToIp
        outputHostField = ud.string(forKey: MPDDefaultKey.outputHost.stringValue(player)) ?? ""
        if let portVal = ud.object(forKey: MPDDefaultKey.outputPort.stringValue(player)) as? Int {
            outputPortField = "\(portVal)"
        } else {
            outputPortField = ""
        }
        let storedPassword = ud.string(forKey: MPDDefaultKey.password.stringValue(player)) ?? ""
        passwordField = storedPassword
        appliedPassword = storedPassword
        customPlayerName = ud.string(forKey: MPDDefaultKey.customPlayerName.stringValue(player)) ?? ""
        isHidden = ud.bool(forKey: MPDDefaultKey.hidden.stringValue(player))
        useHTTPCoverArt = ud.bool(forKey: MPDDefaultKey.useHttpCoverArt.stringValue(player))
        albumGroupingSelection = ud.string(forKey: MPDDefaultKey.albumGrouping.stringValue(player)) ?? "albumartist"
        databaseStatusText = ""
        databaseArtists = "-"
        databaseAlbums = "-"
        databaseSongs = "-"
        Task {
            if let browse = player.browse as? MPDBrowse {
                databaseStatusText = (try? await browse.databaseStatus()) ?? ""
                if let stats = try? await browse.databaseStats() {
                    databaseArtists = "\(stats.artists)"
                    databaseAlbums = "\(stats.albums)"
                    databaseSongs = "\(stats.songs)"
                }
            }
        }
    }

    func commitConnectionSettingsIfNeeded() {
        let trimmedPassword = passwordField.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIp = ipAddressField.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsApply = trimmedPassword != appliedPassword
            || trimmedIp != appliedIpAddress
            || connectToIp != appliedConnectToIp
        guard needsApply else { return }
        appliedPassword = trimmedPassword
        appliedIpAddress = trimmedIp
        appliedConnectToIp = connectToIp
        player.applyConnectionSettingsChange()
    }
    
    func updateStreamSettings() {
        let ud = player.userDefaults
        let trimmedHost = outputHostField.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHost.isEmpty {
            ud.removeObject(forKey: MPDDefaultKey.outputHost.stringValue(player))
        } else {
            ud.set(outputHostField, forKey: MPDDefaultKey.outputHost.stringValue(player))
        }

        let portInt = Int(outputPortField)
        if let portInt {
            ud.set(portInt, forKey: MPDDefaultKey.outputPort.stringValue(player))
        } else {
            ud.removeObject(forKey: MPDDefaultKey.outputPort.stringValue(player))
        }

        player.attributes = MPDPlayer.PlayerAttributes(uuid: player.attributes.uuid,
                                                       name: player.attributes.name,
                                                       type: player.attributes.type,
                                                       version: player.attributes.version,
                                                       host: player.attributes.host,
                                                       port: player.attributes.port,
                                                       password: player.attributes.password,
                                                       useHttpCoverArt: player.attributes.useHttpCoverArt,
                                                       manual: player.attributes.manual,
                                                       albumGrouping: player.attributes.albumGrouping,
                                                       coverFilename: player.attributes.coverFilename,
                                                       outputHost: trimmedHost,
                                                       outputPort: portInt ?? 0)

        player.objectWillChange.send()
    }
    
    func updatePasswordSettings() {
        let ud = player.userDefaults
        let trimmed = passwordField.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            ud.removeObject(forKey: MPDDefaultKey.password.stringValue(player))
        } else {
            ud.set(trimmed, forKey: MPDDefaultKey.password.stringValue(player))
        }

        player.attributes = MPDPlayer.PlayerAttributes(uuid: player.attributes.uuid,
                                                       name: player.attributes.name,
                                                       type: player.attributes.type,
                                                       version: player.attributes.version,
                                                       host: player.attributes.host,
                                                       port: player.attributes.port,
                                                       password: trimmed.isEmpty ? nil : trimmed,
                                                       useHttpCoverArt: player.attributes.useHttpCoverArt,
                                                       manual: player.attributes.manual,
                                                       albumGrouping: player.attributes.albumGrouping,
                                                       coverFilename: player.attributes.coverFilename,
                                                       outputHost: player.attributes.outputHost,
                                                       outputPort: player.attributes.outputPort)

        player.objectWillChange.send()
    }

    func updateIPAddressSettings() {
        let ud = player.userDefaults
        if ipAddressField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ud.removeObject(forKey: MPDDefaultKey.ipAddress.stringValue(player))
        } else {
            ud.set(ipAddressField, forKey: MPDDefaultKey.ipAddress.stringValue(player))
        }
        ud.set(connectToIp, forKey: MPDDefaultKey.connectToIpAddress.stringValue(player))
        player.objectWillChange.send()
    }

    @ViewBuilder private func playerInformationFooter() -> some View {
        // Adjust the footer based on the selected type if needed
        switch selectedType {
        case .volumio:
            Text(String(localized: "Note that for Volumio players, the playqueue in Rigelian is not synchronized with the playqueue shown through the Volumio web interface.", bundle: .module))
        default:
            EmptyView()
        }
    }
}

struct MPDChangeNameTip: Tip {
    var id: String { "mpd.changename" }
    var title: Text { Text("Change name") }
    var message: Text? { Text("You can change the player's name that will be displayed in Rigelian.") }
    var image: Image? { Image(systemName: "rectangle.and.pencil.and.ellipsis") }
    var rules: [Self.Rule] { [] }
    var actions: [Self.Action] { [] }
    var options: [any TipOption] { [] }
}

#if DEBUG
struct OpenHomeSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        // Note: This preview won't work without a real OpenHomePlayer instance
        // It's provided for structure reference only
        Text("OpenHome Settings Preview")
            .previewDisplayName("OpenHome Settings")
    }
}
#endif

