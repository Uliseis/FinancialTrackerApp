import Foundation
import SwiftData
import CoreModel
import ImportFromPostgresCore

@MainActor
func runImport() throws {
    let args = parseArgs()
    let dumpData = try Data(contentsOf: args.dumpURL)
    let doc = try JSONDecoder().decode(DumpDocument.self, from: dumpData)

    let schema = Schema(CoreModelSchema.allTypes)
    let config = ModelConfiguration(
        schema: schema,
        url: args.storeURL,
        cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [config])
    let ctx = ModelContext(container)
    let summary = try PostgresImporter.importDump(doc, into: ctx)
    printSummary(summary, storeURL: args.storeURL)
}

struct ImportArgs {
    let dumpURL: URL
    let storeURL: URL
}

func parseArgs() -> ImportArgs {
    var dump: String?
    var store: String?
    var i = 1
    let argv = CommandLine.arguments
    while i < argv.count {
        let a = argv[i]
        switch a {
        case "--dump":
            i += 1
            if i < argv.count { dump = argv[i] }
        case "--store":
            i += 1
            if i < argv.count { store = argv[i] }
        case "-h", "--help":
            printUsage()
            exit(0)
        default:
            FileHandle.standardError.write(Data("Unknown argument: \(a)\n".utf8))
            printUsage()
            exit(2)
        }
        i += 1
    }
    guard let dump, let store else {
        printUsage()
        exit(2)
    }
    return ImportArgs(
        dumpURL: URL(fileURLWithPath: dump),
        storeURL: URL(fileURLWithPath: store)
    )
}

func printUsage() {
    let msg = """
    Usage: ImportFromPostgres --dump <dump.json> --store <output.store>

    Reads a JSON dump produced by Tools/ExportFromPostgres and writes the rows
    into a SwiftData ModelContainer at <output.store>. The container is opened
    with cloudKitDatabase=.none; sync is the iOS app's job.
    """
    print(msg)
}

func printSummary(_ s: ImportSummary, storeURL: URL) {
    print("Imported into \(storeURL.path):")
    print("  connections:         \(s.connections)")
    print("  account_groups:      \(s.accountGroups)")
    print("  account_spaces:      \(s.accountSpaces)")
    print("  accounts:            \(s.accounts)")
    print("  categories:          \(s.categories)")
    print("  category_rules:      \(s.categoryRules)")
    print("  transfer_routes:     \(s.transferRoutes)")
    print("  budgets:             \(s.budgets)")
    print("  fx_rates:            \(s.fxRates)")
    print("  transfer_groups:     \(s.transferGroups)")
    print("  transactions:        \(s.transactions)")
    print("  shared_expense_grps: \(s.sharedExpenseGroups)")
    print("  portfolio_valuations:\(s.portfolioValuations)")
    print("  sync_runs:           \(s.syncRuns)")
    print("Backfills:")
    print("  categorySource NULL -> .bank: \(s.categorySourceBackfilled)")
    print("  attributionMonth derived:     \(s.attributionMonthBackfilled)")
}

do {
    try MainActor.assumeIsolated { try runImport() }
} catch {
    FileHandle.standardError.write(Data("import failed: \(error)\n".utf8))
    exit(1)
}
