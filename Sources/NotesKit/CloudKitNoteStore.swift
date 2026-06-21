import Foundation
import CoreData
// NSPersistentCloudKitContainer is in CoreData, but CloudKit.framework must
// still be linked for a sandboxed app to reach the CloudKit daemon. Importing
// it here ensures the framework is linked into anything that uses this store.
import CloudKit

/// Core Data managed object backing a synced note. All attributes are optional
/// or have defaults (a CloudKit requirement) and there are no unique
/// constraints (also required) — uniqueness on `id` is enforced in code.
@objc(CDNote)
final class CDNote: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var content: String?
    @NSManaged var colorToken: String?
    @NSManaged var fontName: String?
    @NSManaged var fontSize: Double
    @NSManaged var collapsed: Bool
    @NSManaged var createdAt: Date?
    @NSManaged var modifiedAt: Date?
    @NSManaged var deletedAt: Date?
}

/// Cross-device sync via Core Data + `NSPersistentCloudKitContainer`.
///
/// This is a drop-in replacement for `JSONNoteStore`: same `NoteStore`
/// protocol, so swapping `AppDelegate.store` to use it is the only UI-side
/// change. It compiles and runs locally as plain Core Data today; CloudKit
/// sync activates once the app has the iCloud entitlement (a signed app bundle
/// + Apple Developer membership — see the README).
///
/// What syncs: the note records. What does NOT: window geometry — that stays
/// device-local in a JSON sidecar, exactly as before.
public final class CloudKitNoteStore: NoteStore {
    public var onChange: (() -> Void)?

    private let container: NSPersistentCloudKitContainer
    private var context: NSManagedObjectContext { container.viewContext }

    private var layoutsByID: [UUID: NoteLayout] = [:]
    private let layoutsURL: URL

    /// - Parameters:
    ///   - containerIdentifier: your CloudKit container, e.g.
    ///     `iCloud.design.wooj.StickySync`. Must match the app's entitlement.
    ///   - inMemory: use an ephemeral store with no CloudKit (handy for tests
    ///     and for running before the iCloud entitlement exists).
    public init(containerIdentifier: String = "iCloud.design.wooj.StickySync",
                inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(
            name: "StickySync",
            managedObjectModel: CloudKitNoteStore.makeModel()
        )
        layoutsURL = CloudKitNoteStore.defaultLayoutsURL()

        if let description = container.persistentStoreDescriptions.first {
            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
                description.cloudKitContainerOptions = nil
            } else {
                description.cloudKitContainerOptions =
                    NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
                // Required for CloudKit sync + for waking the UI on remote edits.
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber,
                                      forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            }
        }

        // Diagnostic: CloudKit setup/import/export errors are redacted as
        // <private> in the system log, so log them ourselves (unredacted, via
        // the app's own NSError) to pin down why mirroring fails to initialize.
        if !inMemory {
            NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: container, queue: .main
            ) { notification in
                guard let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event else { return }
                let kind: String
                switch event.type {
                case .setup: kind = "setup"
                case .import: kind = "import"
                case .export: kind = "export"
                @unknown default: kind = "other"
                }
                if let error = event.error {
                    NSLog("%@", "StickySync[CK] \(kind) FAILED: \(error as NSError)")
                } else if event.endDate != nil {
                    NSLog("%@", "StickySync[CK] \(kind) ok")
                }
            }
        }

        container.loadPersistentStores { _, error in
            if let error = error {
                NSLog("StickySync: Core Data store failed to load: \(error)")
            }
        }

        #if DEBUG
        // One-time schema bootstrap. Run a *Development* (Xcode) build with the
        // env var INIT_CK_SCHEMA=1 to (re)create the CloudKit schema from the
        // current model, then deploy Development → Production in the CloudKit
        // Console. Production can't create fields at runtime, so any new model
        // field (e.g. deletedAt) must be published this way — otherwise every
        // export fails with "Invalid Arguments / Cannot create or modify field
        // '…' in production schema" and all sync silently halts.
        if !inMemory, ProcessInfo.processInfo.environment["INIT_CK_SCHEMA"] == "1" {
            do {
                try container.initializeCloudKitSchema(options: [])
                NSLog("%@", "StickySync[CK] initializeCloudKitSchema SUCCEEDED — now deploy Development → Production in the CloudKit Console")
            } catch {
                NSLog("%@", "StickySync[CK] initializeCloudKitSchema FAILED: \(error as NSError)")
            }
        }
        #endif

        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

        loadLayouts()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange(_:)),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func handleRemoteChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    // MARK: - NoteStore (notes live in CloudKit-backed Core Data)

    public func allNotes() -> [Note] {
        let request = NSFetchRequest<CDNote>(entityName: "CDNote")
        request.predicate = NSPredicate(format: "deletedAt == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let results = (try? context.fetch(request)) ?? []
        return results.compactMap(Self.note(from:))
    }

    public func note(id: UUID) -> Note? {
        guard let cd = fetch(id: id), cd.deletedAt == nil else { return nil }
        return Self.note(from: cd)
    }

    public func add(_ note: Note) {
        apply(note, to: makeCDNote())
        save()
    }

    public func update(_ note: Note) {
        let cd = fetch(id: note.id) ?? makeCDNote()
        apply(note, to: cd)
        cd.modifiedAt = Date()
        save()
    }

    public func softDelete(id: UUID) {
        guard let cd = fetch(id: id) else { return }
        let now = Date()
        cd.deletedAt = now
        cd.modifiedAt = now
        save()
    }

    // MARK: - NoteStore (layouts stay device-local)

    public func layout(for id: UUID) -> NoteLayout? { layoutsByID[id] }

    public func setLayout(_ layout: NoteLayout) {
        layoutsByID[layout.noteID] = layout
        saveLayouts()
    }

    // MARK: - Mapping

    private func fetch(id: UUID) -> CDNote? {
        let request = NSFetchRequest<CDNote>(entityName: "CDNote")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func makeCDNote() -> CDNote {
        let entity = NSEntityDescription.entity(forEntityName: "CDNote", in: context)!
        return CDNote(entity: entity, insertInto: context)
    }

    private func apply(_ note: Note, to cd: CDNote) {
        cd.id = note.id
        cd.content = note.content
        cd.colorToken = note.colorToken
        cd.fontName = note.fontName
        cd.fontSize = note.fontSize
        cd.collapsed = note.collapsed
        cd.createdAt = note.createdAt
        cd.modifiedAt = note.modifiedAt
        cd.deletedAt = note.deletedAt
    }

    private static func note(from cd: CDNote) -> Note? {
        guard let id = cd.id else { return nil }
        return Note(
            id: id,
            content: cd.content ?? "",
            colorToken: cd.colorToken ?? Palette.defaultToken,
            fontName: cd.fontName ?? FontCatalog.defaultID,
            fontSize: cd.fontSize,
            collapsed: cd.collapsed,
            createdAt: cd.createdAt ?? Date(),
            modifiedAt: cd.modifiedAt ?? Date(),
            deletedAt: cd.deletedAt
        )
    }

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            NSLog("StickySync: save failed: \(error)")
        }
    }

    // MARK: - Programmatic model

    private static func makeModel() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = "CDNote"
        entity.managedObjectClassName = "CDNote"

        func attribute(_ name: String,
                       _ type: NSAttributeType,
                       optional: Bool,
                       defaultValue: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = optional
            if let defaultValue { a.defaultValue = defaultValue }
            return a
        }

        entity.properties = [
            attribute("id", .UUIDAttributeType, optional: true),
            attribute("content", .stringAttributeType, optional: true, defaultValue: ""),
            attribute("colorToken", .stringAttributeType, optional: true, defaultValue: Palette.defaultToken),
            attribute("fontName", .stringAttributeType, optional: true, defaultValue: FontCatalog.defaultID),
            attribute("fontSize", .doubleAttributeType, optional: false, defaultValue: NSNumber(value: 15.0)),
            attribute("collapsed", .booleanAttributeType, optional: false, defaultValue: NSNumber(value: false)),
            attribute("createdAt", .dateAttributeType, optional: true),
            attribute("modifiedAt", .dateAttributeType, optional: true),
            attribute("deletedAt", .dateAttributeType, optional: true)
        ]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    // MARK: - Device-local layout sidecar

    private static func defaultLayoutsURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true)) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("StickySync", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("layouts.json")
    }

    private func loadLayouts() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: layoutsURL),
              let layouts = try? decoder.decode([NoteLayout].self, from: data) else { return }
        layoutsByID = Dictionary(layouts.map { ($0.noteID, $0) }) { _, last in last }
    }

    private func saveLayouts() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Array(layoutsByID.values)) else { return }
        try? data.write(to: layoutsURL, options: .atomic)
    }
}
