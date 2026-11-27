import Foundation
import GRDB
import VietText

/// Chỉ mục tìm kiếm toàn văn của thư viện (`.cache/index.sqlite`), dựng trên SQLite FTS5.
///
/// Lược đồ theo `docs/dinh-dang-tep.md` mục 6. Chỉ mục dựng lại được hoàn toàn từ các tệp, nên khi
/// `indexVersion` khác hằng số trong code, hoặc tệp hỏng, Hệ thống xoá và tạo lại.
///
/// Cách sắp `rowid`: câu Kinh Thánh nằm trong dải `rowid >= verseRowIDBase`, các loại khác nằm dưới dải đó.
/// `rowid` của `items_fts` luôn bằng `rowid` của `items`. Nhờ vậy tìm không gồm câu Kinh Thánh chỉ quét
/// phần chỉ mục FTS dưới dải câu (FTS5 đẩy điều kiện `rowid` xuống tận danh sách tài liệu), không chậm đi dù có
/// hàng chục nghìn câu.
public actor LibraryIndex {
    /// Phiên bản lược đồ. Tăng khi đổi lược đồ hoặc cách gộp chữ; chỉ mục cũ sẽ bị xoá và dựng lại.
    public static let indexVersion = 1

    /// Điểm của kết quả có `subtitle` đúng bằng số người dùng gõ.
    public static let exactNumberScore = 1_000_000.0
    /// Điểm của kết quả có `subtitle` bắt đầu bằng số người dùng gõ nhưng dài hơn (gõ "12" ra "125").
    public static let numberPrefixScore = 500_000.0

    /// Collation so sánh tên theo chữ đã gộp dấu ("Ân" đứng trước "Ca", "Đấng" sau "Ca").
    static let foldedCollationName = "vietfold"

    /// Dải `rowid` dành cho câu Kinh Thánh.
    static let verseRowIDBase: Int64 = 1 << 40

    private let dbQueue: DatabaseQueue

    /// Tạo hoặc mở chỉ mục tại `databaseURL`. Thư mục cha được tạo nếu chưa có.
    public init(databaseURL: URL) throws {
        try self.init(databaseURL: databaseURL, indexVersion: Self.indexVersion)
    }

    /// Như ``init(databaseURL:)`` với phiên bản lược đồ chỉ định; dùng cho test đổi phiên bản.
    init(databaseURL: URL, indexVersion: Int) throws {
        dbQueue = try Self.openPrepared(at: databaseURL, indexVersion: indexVersion)
    }

    // MARK: - Ghi

    /// Thêm hoặc thay các mục (khớp theo `id`), tất cả trong một giao dịch.
    public func upsert(_ entries: [IndexEntry]) throws {
        guard !entries.isEmpty else { return }
        try dbQueue.write { db in
            var allocator = try RowIDAllocator(db)
            let findRowID = try db.cachedStatement(sql: "SELECT rowid FROM items WHERE id = ?")
            let deleteFTS = try db.cachedStatement(sql: "DELETE FROM items_fts WHERE rowid = ?")
            let deleteItem = try db.cachedStatement(sql: "DELETE FROM items WHERE rowid = ?")
            let updateItem = try db.cachedStatement(
                sql: "UPDATE items SET kind = ?, title = ?, subtitle = ?, path = ?, modifiedAt = ? WHERE rowid = ?"
            )
            let insertItem = try db.cachedStatement(
                sql: """
                    INSERT INTO items(rowid, id, kind, title, subtitle, path, modifiedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """
            )
            let insertFTS = try db.cachedStatement(
                sql: "INSERT INTO items_fts(rowid, id, kind, title_f, subtitle_f, body_f) VALUES (?, ?, ?, ?, ?, ?)"
            )

            for entry in entries {
                let modifiedAt = entry.modifiedAt.map { $0.ISO8601Format() }
                var rowID = try Int64.fetchOne(findRowID, arguments: [entry.id])
                if let existing = rowID {
                    try deleteFTS.execute(arguments: [existing])
                    if Self.isVerseRowID(existing) == (entry.kind == .verse) {
                        try updateItem.execute(
                            arguments: [
                                entry.kind.rawValue, entry.title, entry.subtitle, entry.path, modifiedAt, existing,
                            ]
                        )
                    } else {
                        // Đổi giữa câu Kinh Thánh và loại khác: chuyển sang dải rowid đúng.
                        try deleteItem.execute(arguments: [existing])
                        rowID = nil
                    }
                }
                let ftsRowID: Int64
                if let rowID {
                    ftsRowID = rowID
                } else {
                    ftsRowID = allocator.next(for: entry.kind)
                    try insertItem.execute(
                        arguments: [
                            ftsRowID, entry.id, entry.kind.rawValue, entry.title, entry.subtitle, entry.path,
                            modifiedAt,
                        ]
                    )
                }
                try insertFTS.execute(
                    arguments: [
                        ftsRowID, entry.id, entry.kind.rawValue, VietText.fold(entry.title),
                        entry.subtitle.map(VietText.fold), entry.body.map(VietText.fold),
                    ]
                )
            }
        }
    }

    /// Xoá các mục theo `id`. Mã không có trong chỉ mục thì bỏ qua.
    public func remove(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            let findRowID = try db.cachedStatement(sql: "SELECT rowid FROM items WHERE id = ?")
            let deleteFTS = try db.cachedStatement(sql: "DELETE FROM items_fts WHERE rowid = ?")
            let deleteItem = try db.cachedStatement(sql: "DELETE FROM items WHERE rowid = ?")
            for id in ids {
                guard let rowID = try Int64.fetchOne(findRowID, arguments: [id]) else { continue }
                try deleteFTS.execute(arguments: [rowID])
                try deleteItem.execute(arguments: [rowID])
            }
        }
    }

    /// Xoá mọi mục thuộc một loại.
    public func removeAll(kind: IndexKind) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM items_fts WHERE rowid IN (SELECT rowid FROM items WHERE kind = ?)",
                arguments: [kind.rawValue]
            )
            try db.execute(sql: "DELETE FROM items WHERE kind = ?", arguments: [kind.rawValue])
        }
    }

    // MARK: - Đọc

    /// Số mục thuộc một loại.
    public func count(kind: IndexKind) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM items WHERE kind = ?", arguments: [kind.rawValue]) ?? 0
        }
    }

    /// Tìm theo chữ người dùng gõ, có dấu hay không dấu đều được.
    ///
    /// - Truy vấn rỗng, `kinds` rỗng hoặc `limit` không dương: trả rỗng.
    /// - Mỗi từ là một tiền tố; mọi từ phải có (AND).
    /// - Truy vấn toàn chữ số: các mục (trừ câu Kinh Thánh) có `subtitle` bắt đầu bằng số đó đứng đầu,
    ///   khớp đúng số trước, khớp tiền tố sau.
    /// - Còn lại xếp theo `bm25` (tên nặng 10, phụ đề 5, nội dung 1), rồi theo tên đã gộp dấu.
    public func search(_ query: String, kinds: Set<IndexKind>, limit: Int = 50) throws -> [SearchHit] {
        guard limit > 0, !kinds.isEmpty else { return [] }
        let terms = VietText.queryTerms(query)
        guard !terms.isEmpty else { return [] }
        let number = terms.count == 1 && terms[0].allSatisfy(\.isASCIIDigit) ? terms[0] : nil
        let matchExpression = Self.matchExpression(terms)

        return try dbQueue.read { db in
            var hits: [SearchHit] = []
            if let number {
                hits = try Self.numberHits(db, number: number, kinds: kinds, limit: limit)
            }
            guard hits.count < limit, let matchExpression else { return hits }
            let seen = Set(hits.map(\.id))
            // Lấy đủ `limit` dòng: số dòng trùng với kết quả số không quá `hits.count`.
            let fullText = try Self.fullTextHits(db, match: matchExpression, kinds: kinds, limit: limit)
            for hit in fullText where !seen.contains(hit.id) && hits.count < limit {
                hits.append(hit)
            }
            return hits
        }
    }

    // MARK: - Mở và lược đồ

    private static func openPrepared(at url: URL, indexVersion: Int) throws -> DatabaseQueue {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            return try openAndMigrate(at: url, indexVersion: indexVersion)
        } catch let error as DatabaseError where isCorruption(error) {
            // Tệp hỏng: chỉ mục dựng lại được từ thư viện, nên xoá và tạo mới.
            removeDatabaseFiles(at: url)
            return try openAndMigrate(at: url, indexVersion: indexVersion)
        }
    }

    private static func isCorruption(_ error: DatabaseError) -> Bool {
        error.resultCode == .SQLITE_NOTADB || error.resultCode == .SQLITE_CORRUPT
    }

    private static func openAndMigrate(at url: URL, indexVersion: Int) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.label = "LibraryIndex"
        configuration.prepareDatabase { db in
            db.add(
                collation: DatabaseCollation(foldedCollationName) { lhs, rhs in
                    let left = VietText.fold(lhs)
                    let right = VietText.fold(rhs)
                    return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
                })
        }
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        try queue.write { db in
            if try storedVersion(db) == String(indexVersion), try db.tableExists("items"),
                try db.tableExists("items_fts")
            {
                return
            }
            try db.execute(
                sql: """
                    DROP TABLE IF EXISTS items_fts;
                    DROP TABLE IF EXISTS items;
                    DROP TABLE IF EXISTS meta;
                    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
                    CREATE TABLE items(
                      id TEXT PRIMARY KEY,
                      kind TEXT NOT NULL,
                      title TEXT NOT NULL,
                      subtitle TEXT,
                      path TEXT,
                      modifiedAt TEXT
                    );
                    CREATE VIRTUAL TABLE items_fts USING fts5(
                      id UNINDEXED, kind UNINDEXED,
                      title_f, subtitle_f, body_f,
                      tokenize = 'unicode61'
                    );
                    """
            )
            try db.execute(
                sql: "INSERT INTO meta(key, value) VALUES ('indexVersion', ?)", arguments: [String(indexVersion)])
        }
        return queue
    }

    private static func storedVersion(_ db: Database) throws -> String? {
        guard try db.tableExists("meta") else { return nil }
        return try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'indexVersion'")
    }

    private static func removeDatabaseFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    // MARK: - Truy vấn

    static func isVerseRowID(_ rowID: Int64) -> Bool {
        rowID >= verseRowIDBase
    }

    /// Mỗi từ thành `"<từ>"*`, nối bằng khoảng trắng (AND). Từ không có chữ hay số (chỉ dấu câu) bị bỏ vì FTS5
    /// không tách được token nào từ nó. Trả `nil` khi không còn từ nào.
    static func matchExpression(_ terms: [String]) -> String? {
        let parts =
            terms
            .filter { !VietText.foldLoose($0).isEmpty }
            .map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Điều kiện giới hạn theo loại, nối sau `WHERE`. `rowidColumn` là cột `rowid` của bảng dẫn truy vấn;
    /// bảng `items` luôn có bí danh `i`.
    private static func kindFilter(_ kinds: Set<IndexKind>, rowidColumn: String) -> (sql: String, args: [String]) {
        let nonVerseKinds = Set(IndexKind.allCases).subtracting([.verse])
        var clauses: [String] = []
        var args: [String] = []
        if !kinds.contains(.verse) {
            clauses.append("\(rowidColumn) < \(verseRowIDBase)")
        } else if kinds == [.verse] {
            clauses.append("\(rowidColumn) >= \(verseRowIDBase)")
        }
        // Dải rowid đã đủ khi lấy mọi loại, chỉ câu, hoặc mọi loại trừ câu.
        if kinds.count < IndexKind.allCases.count, kinds != [.verse], kinds != nonVerseKinds {
            args = kinds.map(\.rawValue).sorted()
            let placeholders = Array(repeating: "?", count: args.count).joined(separator: ", ")
            clauses.append("i.kind IN (\(placeholders))")
        }
        return (clauses.map { " AND " + $0 }.joined(), args)
    }

    private static func numberHits(_ db: Database, number: String, kinds: Set<IndexKind>, limit: Int) throws
        -> [SearchHit]
    {
        // Câu Kinh Thánh không tham gia: địa chỉ như "1 Cô-rinh-tô 13:4" cũng bắt đầu bằng số.
        let numberKinds = kinds.subtracting([.verse])
        guard !numberKinds.isEmpty else { return [] }
        let filter = kindFilter(numberKinds, rowidColumn: "i.rowid")
        let length = number.count
        let sql = """
            SELECT i.id, i.kind, i.title, i.subtitle,
                   substr(i.subtitle, \(length + 1), 1) BETWEEN '0' AND '9' AS isPrefixOnly
            FROM items i
            WHERE substr(i.subtitle, 1, \(length)) = ?\(filter.sql)
            ORDER BY isPrefixOnly, length(i.subtitle), i.subtitle, i.title, i.id
            LIMIT \(limit)
            """
        var arguments: StatementArguments = [number]
        arguments += StatementArguments(filter.args)
        return try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap { row in
            guard let kind = IndexKind(rawValue: row["kind"]) else { return nil }
            let isPrefixOnly: Bool = row["isPrefixOnly"]
            return SearchHit(
                id: row["id"], kind: kind, title: row["title"], subtitle: row["subtitle"],
                score: isPrefixOnly ? numberPrefixScore : exactNumberScore)
        }
    }

    private static func fullTextHits(_ db: Database, match: String, kinds: Set<IndexKind>, limit: Int) throws
        -> [SearchHit]
    {
        let filter = kindFilter(kinds, rowidColumn: "items_fts.rowid")
        // Trọng số bm25 tính cả hai cột UNINDEXED đứng đầu (id, kind), nên đặt 0 cho chúng.
        // Hoà điểm thì xếp theo tên đã gộp dấu bằng collation `vietfold` trên `items.title`, không đọc
        // `items_fts.title_f`: đọc cột đó buộc FTS5 nạp cả dòng nội dung (gồm lời bài hát) cho mọi mục khớp, chậm
        // gần gấp đôi khi truy vấn khớp hàng nghìn mục. Collation chỉ chạy khi hai mục cùng điểm.
        let sql = """
            SELECT i.id, i.kind, i.title, i.subtitle, bm25(items_fts, 0.0, 0.0, 10.0, 5.0, 1.0) AS rank
            FROM items_fts JOIN items i ON i.rowid = items_fts.rowid
            WHERE items_fts MATCH ?\(filter.sql)
            ORDER BY rank, i.title COLLATE \(foldedCollationName), i.title, i.id
            LIMIT \(limit)
            """
        var arguments: StatementArguments = [match]
        arguments += StatementArguments(filter.args)
        return try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap { row in
            guard let kind = IndexKind(rawValue: row["kind"]) else { return nil }
            let rank: Double = row["rank"]
            return SearchHit(id: row["id"], kind: kind, title: row["title"], subtitle: row["subtitle"], score: -rank)
        }
    }
}

/// Cấp `rowid` mới trong từng dải trong một giao dịch ghi.
private struct RowIDAllocator {
    private var nextOrdinary: Int64
    private var nextVerse: Int64

    init(_ db: Database) throws {
        let base = LibraryIndex.verseRowIDBase
        let maxOrdinary = try Int64.fetchOne(db, sql: "SELECT max(rowid) FROM items WHERE rowid < ?", arguments: [base])
        let maxVerse = try Int64.fetchOne(db, sql: "SELECT max(rowid) FROM items WHERE rowid >= ?", arguments: [base])
        nextOrdinary = (maxOrdinary ?? 0) + 1
        nextVerse = (maxVerse ?? (base - 1)) + 1
    }

    mutating func next(for kind: IndexKind) -> Int64 {
        if kind == .verse {
            defer { nextVerse += 1 }
            return nextVerse
        }
        defer { nextOrdinary += 1 }
        return nextOrdinary
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
