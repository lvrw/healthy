import SwiftData
import SwiftUI
import UIKit

/// 远程食物图片加载器。麦当劳图床会校验 Referer，只有带上官网来源才返回 200；
/// SwiftUI 的 AsyncImage 无法设置请求头，所以统一走 URLSession + 内存缓存。
@MainActor
final class FoodImageLoader {
    static let shared = FoodImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var tasks: [String: Task<UIImage?, Never>] = [:]
    private var failedURLs: Set<String> = []

    func image(for urlString: String) async -> UIImage? {
        let key = urlString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        if failedURLs.contains(urlString) { return nil }
        if let running = tasks[urlString] { return await running.value }

        let task = Task<UIImage?, Never> {
            guard let url = URL(string: urlString) else { return nil }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            if url.host?.contains("mcdonalds.com.cn") == true {
                request.setValue("https://www.mcdonalds.com.cn/", forHTTPHeaderField: "Referer")
            }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data) else { return nil }
            return image
        }
        tasks[urlString] = task
        let image = await task.value
        tasks[urlString] = nil
        if let image {
            cache.setObject(image, forKey: key)
        } else {
            failedURLs.insert(urlString)
        }
        return image
    }
}

/// 食物远程图片：有 imageURL 时加载官网产品图，否则退回 SF 图标。
struct FoodRemoteIcon: View {
    let imageURL: String?
    /// 远程图加载失败 / 无 URL 时的兜底 SF Symbol。
    var fallbackSymbol: String = "fork.knife"
    var size: CGFloat = 34

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AppPalette.greenSoft.opacity(0.3)
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(AppPalette.greenDeep)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .background(AppPalette.greenSoft.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
        .task(id: imageURL) {
            image = nil
            guard let imageURL else { return }
            image = await FoodImageLoader.shared.image(for: imageURL)
        }
    }
}

/// 分组封面图：优先用分组里第一张产品图，加载中 / 无图时显示品牌渐变与特征图标。
struct GroupCoverImage: View {
    let imageURL: String?
    /// 无图时叠在渐变上的品牌特征图标。
    var symbol: String?
    var gradient: LinearGradient = LinearGradient(
        colors: [AppPalette.greenDeep, AppPalette.greenDeep.opacity(0.4)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            gradient
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay(.black.opacity(0.15))
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .clipped()
        .task(id: imageURL) {
            image = nil
            guard let imageURL else { return }
            image = await FoodImageLoader.shared.image(for: imageURL)
        }
    }
}

/// 大卡片分组：封面图 + 大标题 + 产品数 + 系统 badge。
struct GroupCard: View {
    let group: FoodGroup
    let count: Int
    let coverImageURL: String?
    let gradient: LinearGradient
    let symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 封面区
            ZStack(alignment: .topTrailing) {
                GroupCoverImage(imageURL: coverImageURL, symbol: symbol, gradient: gradient)
                    .frame(height: 92)
                if group.isBuiltin {
                    Label("系统", systemImage: "lock.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
            }
            // 文字区
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text("\(count) 种")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

/// 虚拟分组 ID：FrequentFood 和无显式 groupID 的 CustomFood 用虚拟分组包装。
extension FoodGroup {
    static let frequentVirtualID = "group.virtual.frequent"
    static let customVirtualID   = "group.virtual.custom"

    /// 虚拟分组：不存在于 SwiftData，但 FoodGroupDetailView 会按 id 特殊处理数据源。
    static func virtualFrequent(count: Int) -> FoodGroup {
        FoodGroup(id: frequentVirtualID, name: "常用饮食", sortOrder: -1, isBuiltin: false)
    }
    static func virtualCustom(count: Int) -> FoodGroup {
        FoodGroup(id: customVirtualID, name: "我的食物", sortOrder: 0, isBuiltin: false)
    }
}


/// 本地营养库维护：内置库只读展示；「常用饮食」由识别保存时自动收集（与自定义区分，可删）；
/// 「我的常吃食物」为手动新增 / 编辑 / 删除。关闭 AI 识别时，两者会和内置库一起参与文字匹配。
struct FoodLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomFood.name, order: .forward) private var customFoods: [CustomFood]
    /// 常用饮食按最近使用倒序，最常/最近吃的排前面。
    @Query(sort: \FrequentFood.lastUsedAt, order: .reverse) private var frequentFoods: [FrequentFood]
    /// 分组：按 sortOrder 升序。
    @Query(sort: \FoodGroup.sortOrder, order: .forward) private var groups: [FoodGroup]

    @State private var searchText = ""
    @State private var showEditor = false
    @State private var editing: CustomFood?
    @State private var showNewGroup = false
    @State private var newGroupName = ""

    // MARK: - 计算属性

    /// 合并后的分组：虚拟分组（常用饮食、我的食物）+ SwiftData 里的真实分组，按 sortOrder 升序。
    private var mergedGroups: [FoodGroup] {
        let virtuals: [FoodGroup] = [
            .virtualFrequent(count: frequentFoods.count),
            .virtualCustom(count: customFoods.filter { $0.groupID == nil }.count),
        ]
        return (virtuals + groups).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 虚拟分组：FrequentFood
    private var virtualFrequent: FoodGroup {
        .virtualFrequent(count: frequentFoods.count)
    }
    /// 虚拟分组：无显式 groupID 的 CustomFood
    private var virtualCustom: FoodGroup {
        .virtualCustom(count: customFoods.filter { $0.groupID == nil }.count)
    }

    /// 给定分组，返回它对应的食物数量（虚拟分组特殊处理）。
    private func count(of group: FoodGroup) -> Int {
        switch group.id {
        case FoodGroup.frequentVirtualID: return frequentFoods.count
        case FoodGroup.customVirtualID:    return customFoods.filter { $0.groupID == nil }.count
        default:                            return customFoods.filter { $0.groupID == group.id }.count
        }
    }

    /// 给定分组，返回它的封面图 URL（虚拟分组无封面返回 nil，真实分组取第一条）。
    private func coverImage(for group: FoodGroup) -> String? {
        switch group.id {
        case FoodGroup.frequentVirtualID:
            return frequentFoods.first?.imageURL
        case FoodGroup.customVirtualID:
            return customFoods.first?.imageURL
        default:
            return customFoods.first(where: { $0.groupID == group.id })?.imageURL
        }
    }

    /// 给定分组，返回品牌渐变色系。
    private func brandGradient(for group: FoodGroup) -> LinearGradient {
        let name = group.name
        if name.contains("麦当劳") {
            return LinearGradient(colors: [Color(red: 0.98, green: 0.2, blue: 0.1), Color(red: 0.99, green: 0.85, blue: 0.1)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if name.contains("瑞幸") {
            return LinearGradient(colors: [Color(red: 0.35, green: 0.2, blue: 0.12), Color(red: 0.85, green: 0.45, blue: 0.12)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if name == "常用饮食" {
            return LinearGradient(colors: [Color.orange, Color.orange.opacity(0.4)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if name == "我的食物" {
            return LinearGradient(colors: [Color.gray.opacity(0.7), Color.gray.opacity(0.35)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [AppPalette.greenDeep, AppPalette.greenDeep.opacity(0.4)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 无产品图时的品牌特征图标。
    private func brandSymbol(for group: FoodGroup) -> String {
        switch group.id {
        case FoodGroup.frequentVirtualID: return "clock.arrow.circlepath"
        case FoodGroup.customVirtualID: return "star.fill"
        default: break
        }
        if group.name.contains("咖啡") || group.name.contains("瑞幸") {
            return "cup.and.saucer.fill"
        }
        if group.name.contains("麦当劳") {
            return "takeoutbag.and.cup.and.straw.fill"
        }
        return "fork.knife"
    }

    private var matchedCustom: [CustomFood] {
        guard !searchText.isEmpty else { return [] }
        return customFoods.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.keywords.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    private var matchedFrequent: [FrequentFood] {
        guard !searchText.isEmpty else { return [] }
        return frequentFoods.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - 视图

    var body: some View {
        Group {
            if searchText.isEmpty {
                groupLibrary
            } else {
                searchResults
            }
        }
        .searchable(text: $searchText, prompt: "搜索食物")
        .navigationTitle("本地营养库")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditor = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showEditor) { FoodLibraryEditView() }
        .sheet(item: $editing) { food in FoodLibraryEditView(editing: food) }
        .alert("新建分组", isPresented: $showNewGroup) {
            TextField("分组名称（如 星巴克）", text: $newGroupName)
            Button("取消", role: .cancel) { newGroupName = "" }
            Button("创建") { createGroup() }
        } message: {
            Text("分组用于把同品牌 / 同场景的食物归类管理，可随时改名或删除。")
        }
    }

    /// 主视图：大卡片分组网格。
    private var groupLibrary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(mergedGroups) { group in
                        NavigationLink {
                            FoodGroupDetailView(group: group)
                        } label: {
                            GroupCard(group: group,
                                      count: count(of: group),
                                      coverImageURL: coverImage(for: group),
                                      gradient: brandGradient(for: group),
                                      symbol: brandSymbol(for: group))
                        }
                        .buttonStyle(.plain)
                        .contextMenu(!group.isBuiltin && !isVirtual(group) ? ContextMenu {
                            Button(role: .destructive) { deleteGroup(group) } label: {
                                Label("删除分组", systemImage: "trash")
                            }
                        } : nil)
                    }
                }
                Button { showNewGroup = true } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("新建分组")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppPalette.greenSoft.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                footer
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("我的营养库")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("\(mergedGroups.count) 个分组 · \(customFoods.count + frequentFoods.count) 种食物")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var footer: some View {
        Text("系统品牌分组（麦当劳、瑞幸）不可修改，自定义分组可以增删 / 改名。")
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchResults: some View {
        List {
            if !matchedFrequent.isEmpty {
                Section("常用饮食") {
                    ForEach(matchedFrequent) { food in
                        frequentRow(food)
                    }
                }
            }
            if !matchedCustom.isEmpty {
                Section("所有食物") {
                    ForEach(matchedCustom) { food in
                        Button { editing = food } label: { customRow(food) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if matchedFrequent.isEmpty && matchedCustom.isEmpty {
                Section {
                    ContentUnavailableView("没有匹配的食物", systemImage: "magnifyingglass")
                }
            }
        }
    }

    private func isVirtual(_ group: FoodGroup) -> Bool {
        group.id == FoodGroup.frequentVirtualID || group.id == FoodGroup.customVirtualID
    }

    private func createGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        newGroupName = ""
        guard !name.isEmpty else { return }
        let order = (groups.map(\.sortOrder).max() ?? -1) + 1
        context.insert(FoodGroup(name: name, sortOrder: order))
        try? context.save()
    }

    /// 删除分组：旗下食物的 groupID 置空（移回未分组），不删除食物本身。
    private func deleteGroup(_ group: FoodGroup) {
        for food in customFoods where food.groupID == group.id {
            food.groupID = nil
        }
        context.delete(group)
        try? context.save()
    }

    private func builtInRow(_ food: FoodItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(.subheadline.weight(.medium))
                Text(food.portion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(food.nutrition.energyKcal.rounded())) 千卡")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func customRow(_ food: CustomFood) -> some View {
        HStack(spacing: 12) {
            FoodRemoteIcon(imageURL: food.imageURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(.subheadline.weight(.medium))
                Text(food.portion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !food.keywords.isEmpty {
                    Text(food.keywords.joined(separator: "、"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("\(Int(food.nutrition.energyKcal.rounded())) 千卡")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// 常用饮食行：橙色时钟图标区别于「自定义」的绿色星标，右侧显示累积次数与热量。
    private func frequentRow(_ food: FrequentFood) -> some View {
        HStack(spacing: 12) {
            FoodRemoteIcon(imageURL: food.imageURL, fallbackSymbol: "clock.arrow.circlepath")
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(.subheadline.weight(.medium))
                Text(food.portion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("已记录 \(food.useCount) 次")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text("\(Int(food.nutrition.energyKcal.rounded())) 千卡")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func delete(_ food: CustomFood) {
        context.delete(food)
        try? context.save()
    }

    private func deleteFrequent(_ food: FrequentFood) {
        context.delete(food)
        try? context.save()
    }
}

/// 分组详情：列出该分组下的所有食物，可移出分组 / 删除，也可向分组内新增食物、重命名或删除分组。
struct FoodGroupDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let group: FoodGroup

    @Query(sort: \CustomFood.name, order: .forward) private var allCustom: [CustomFood]
    @Query(sort: \FrequentFood.lastUsedAt, order: .reverse) private var allFrequent: [FrequentFood]

    @State private var showEditor = false
    @State private var editing: CustomFood?
    @State private var editingFrequent: FrequentFood?

    /// 数据源：按 group.id 推断（虚拟分组 / 真实分组）。
    private enum Source { case frequent, ungroupedCustom, realGroup(String) }
    private var source: Source {
        switch group.id {
        case FoodGroup.frequentVirtualID: return .frequent
        case FoodGroup.customVirtualID:   return .ungroupedCustom
        default:                          return .realGroup(group.id)
        }
    }

    // MARK: 各数据源的内容

    private var isVirtual: Bool {
        switch source { case .frequent, .ungroupedCustom: return true; default: return false }
    }

    private var frequentItems: [FrequentFood] { allFrequent }
    private var customItems: [CustomFood] {
        switch source {
        case .ungroupedCustom:  return allCustom.filter { $0.groupID == nil }
        case .realGroup(let id): return allCustom.filter { $0.groupID == id }
        default: return []
        }
    }
    private var itemCount: Int {
        switch source {
        case .frequent:         return frequentItems.count
        case .ungroupedCustom, .realGroup: return customItems.count
        }
    }

    // MARK: Body

    var body: some View {
        List {
            switch source {
            case .frequent:         frequentSection
            case .ungroupedCustom, .realGroup: customSection
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !group.isBuiltin && !isVirtual {
                    Menu {
                        Button { showEditor = true } label: {
                            Label("添加食物到此分组", systemImage: "plus")
                        }
                        Button { /* rename - skipped */ } label: {
                            Label("重命名分组", systemImage: "pencil")
                        }.disabled(true)
                        Button(role: .destructive) { /* delete - skipped */ } label: {
                            Label("删除分组", systemImage: "trash")
                        }.disabled(true)
                    } label: { Image(systemName: "ellipsis.circle") }
                } else if !isVirtual {
                    // 内置分组：展示"仅浏览"标记
                    Text("只读").foregroundStyle(.tertiary).font(.caption)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if case .realGroup(let gid) = source {
                FoodLibraryEditView(groupID: gid)
            } else {
                FoodLibraryEditView()
            }
        }
        .sheet(item: $editing) { food in FoodLibraryEditView(editing: food) }
    }

    // MARK: Sections

    private var frequentSection: some View {
        Section {
            ForEach(frequentItems) { food in
                Button { editingFrequent = food } label: {
                    HStack(spacing: 12) {
                        FoodRemoteIcon(imageURL: food.imageURL, fallbackSymbol: "clock.arrow.circlepath")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name).font(.subheadline.weight(.medium))
                            Text("已记录 \(food.useCount) 次 · \(Int(food.nutrition.energyKcal.rounded())) 千卡")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(food.portion).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { deleteFrequent(food) } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
            if frequentItems.isEmpty {
                emptyState("还没有饮食记录。")
            }
        } header: {
            Text("常用饮食（\(frequentItems.count) 种 · 自动收集）")
        } footer: {
            Text("在「识别食物」里保存饮食时自动累积，同名会合并次数。")
        }
        .confirmationDialog("编辑常用饮食", isPresented: Binding(
            get: { editingFrequent != nil },
            set: { if !$0 { editingFrequent = nil } }
        ), titleVisibility: .visible) {
            Button("复制到我的食物中编辑") {
                guard let f = editingFrequent else { return }
                let newFood = CustomFood(name: f.name, keywords: [f.name],
                                         portion: f.portion, nutrition: f.nutrition,
                                         groupID: nil,
                                         imageURL: f.imageURL)
                context.insert(newFood)
                try? context.save()
                editing = newFood
                editingFrequent = nil
            }
            Button("仅删除此记录", role: .destructive) {
                if let f = editingFrequent { deleteFrequent(f) }
                editingFrequent = nil
            }
            Button("取消", role: .cancel) { editingFrequent = nil }
        } message: {
            Text("常用饮食由识别自动累积，不能直接修改；可复制为我的食物后编辑。")
        }
    }

    private var customSection: some View {
        Section {
            ForEach(customItems) { food in
                Button {
                    if !group.isBuiltin { editing = food }
                } label: {
                    HStack(spacing: 12) {
                        FoodRemoteIcon(imageURL: food.imageURL)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name).font(.subheadline.weight(.medium))
                            Text(food.portion).font(.caption).foregroundStyle(.secondary)
                            if !food.keywords.isEmpty {
                                Text(food.keywords.joined(separator: "、"))
                                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text("\(Int(food.nutrition.energyKcal.rounded())) 千卡")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !group.isBuiltin {
                        Button { moveOut(food) } label: {
                            Label("移出分组", systemImage: "arrow.up.right")
                        }.tint(.orange)
                        Button(role: .destructive) { delete(food) } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            if customItems.isEmpty {
                switch source {
                case .ungroupedCustom:
                    emptyState("还没有自建食物。点「+」添加。")
                case .realGroup where group.isBuiltin:
                    emptyState("系统维护的品牌库，暂时没有产品。")
                default:
                    emptyState("这个分组还没有食物。点「+」添加。")
                }
            }
        } header: {
            HStack(spacing: 6) {
                Text("分组内食物（\(itemCount) 种）")
                Spacer()
                if group.isBuiltin {
                    Label("系统维护", systemImage: "lock.fill")
                        .font(.caption2).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(AppPalette.greenDeep.opacity(0.7), in: Capsule())
                }
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
    }

    // MARK: Helpers

    private func moveOut(_ food: CustomFood) {
        food.groupID = nil
        try? context.save()
    }
    private func delete(_ food: CustomFood) {
        context.delete(food)
        try? context.save()
    }
    private func deleteFrequent(_ food: FrequentFood) {
        context.delete(food)
        try? context.save()
    }
}
