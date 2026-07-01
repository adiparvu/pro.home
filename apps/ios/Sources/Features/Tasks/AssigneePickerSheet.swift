import SwiftUI

// MARK: - Assignee picker sheet

struct AssigneePickerSheet: View {
    @EnvironmentObject private var familyService: FamilyService
    @Binding var assigneeIds: [String]
    @Binding var assigneeNames: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var customName = ""
    @State private var showCustom = false

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if !familyService.members.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("FAMILY MEMBERS")
                                    .font(AppFont.label)
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                                    .padding(.leading, AppSpacing.xxs)
                                MemberPickerView(selectedIds: $assigneeIds, selectedNames: $assigneeNames)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("SOMEONE ELSE")
                                .font(AppFont.label)
                                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                                .padding(.leading, AppSpacing.xxs)

                            if showCustom {
                                HStack(spacing: 10) {
                                    TextField("Name", text: $customName)
                                        .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                                        .padding(.horizontal, AppSpacing.base).padding(.vertical, 11)
                                        .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: 12))
                                    Button {
                                        let n = customName.trimmingCharacters(in: .whitespaces)
                                        guard !n.isEmpty else { return }
                                        let fakeId = "custom_\(n)"
                                        if !assigneeIds.contains(fakeId) {
                                            assigneeIds.append(fakeId)
                                            assigneeNames.append(n)
                                        }
                                        customName = ""
                                        showCustom = false
                                        HapticFeedback.success()
                                    } label: {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 28)).foregroundStyle(Color.accentColor)
                                    }
                                    .accessibilityLabel("Confirm assignee")
                                }
                            } else {
                                Button {
                                    showCustom = true
                                    HapticFeedback.impact(.light)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "person.badge.plus").font(.system(size: 14)).foregroundStyle(Color.accentColor)
                                        Text("Add someone else…").font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.6))
                                        Spacer()
                                    }
                                    .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
                                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }

                            if !assigneeIds.filter({ $0.hasPrefix("custom_") }).isEmpty {
                                ForEach(assigneeIds.filter { $0.hasPrefix("custom_") }, id: \.self) { id in
                                    let name = String(id.dropFirst("custom_".count))
                                    HStack {
                                        Image(systemName: "person.fill").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                                        Text(name).font(.system(size: 14)).foregroundStyle(.primary)
                                        Spacer()
                                        Button {
                                            assigneeIds.removeAll { $0 == id }
                                            assigneeNames.removeAll { $0 == name }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.primary.opacity(0.3))
                                        }
                                        .accessibilityLabel("Remove \(name)")
                                    }
                                    .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
                                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Assign Task").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

// MARK: - DateFormatter helper

extension DateFormatter {
    @discardableResult
    func also(_ block: (DateFormatter) -> Void) -> DateFormatter {
        block(self)
        return self
    }
}
