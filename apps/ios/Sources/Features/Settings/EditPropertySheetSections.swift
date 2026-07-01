import SwiftUI
import MapKit
import CoreLocation

extension EditPropertySheet {

    // MARK: - Map

    var mapToggleButton: some View {
        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showMap.toggle() } } label: {
            HStack {
                Image(systemName: "map.fill").foregroundStyle(Color.accentColor)
                Text("Location on map").font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                Spacer()
                Image(systemName: showMap ? "chevron.up" : "chevron.down").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                if latitude != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 14)) }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder var mapPickerSection: some View {
        ZStack {
            Map(position: $mapPosition)
                .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onMapCameraChange { ctx in
                    latitude = ctx.camera.centerCoordinate.latitude
                    longitude = ctx.camera.centerCoordinate.longitude
                    latText = String(format: "%.6f", ctx.camera.centerCoordinate.latitude)
                    lonText = String(format: "%.6f", ctx.camera.centerCoordinate.longitude)
                }
            VStack(spacing: 0) {
                Image(systemName: "mappin.circle.fill").font(.system(size: 30, weight: .semibold)).foregroundStyle(.red).shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                Image(systemName: "triangle.fill").font(.system(size: 7)).foregroundStyle(.red).rotationEffect(.degrees(180)).offset(y: -3)
                Spacer()
            }.padding(.top, 46)
            VStack { Spacer(); HStack {
                Button { Task { await reverseGeocode() } } label: {
                    Label("Apply address", systemImage: "arrow.up.left.square.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 7).background(.blue, in: Capsule())
                }.buttonStyle(.plain).padding(.leading, 10).padding(.bottom, 10)
                Spacer()
                Button { Task { await useCurrentLocation() } } label: {
                    ZStack {
                        Circle().fill(.ultraThinMaterial).frame(width: 36, height: 36)
                        if isLocating { ProgressView().tint(.accentColor).scaleEffect(0.7) }
                        else { Image(systemName: "location.fill").font(.system(size: 14)).foregroundStyle(Color.accentColor) }
                    }
                }.buttonStyle(.plain).padding(.trailing, 10).padding(.bottom, 10)
            }}
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8))

        HStack(spacing: 8) {
            formCoordField("Latitude", text: $latText, placeholder: "e.g. 44.426800")
            formCoordField("Longitude", text: $lonText, placeholder: "e.g. 26.102500")
            Button { applyManualCoords() } label: {
                Image(systemName: "arrow.right.circle.fill").font(.system(size: 28)).foregroundStyle(Color.accentColor)
            }.buttonStyle(.plain)
            .accessibilityLabel("Apply coordinates")
        }.padding(.top, 8)
    }

    // MARK: - Story

    var storySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STORY").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4).padding(.top, 20).padding(.bottom, 0)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                if story.isEmpty {
                    Text("Write a story about this property…").font(.system(size: 15)).foregroundStyle(Color.primary.opacity(0.28))
                        .padding(.horizontal, 16).padding(.vertical, 13)
                }
                TextEditor(text: $story).font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                    .scrollContentBackground(.hidden).background(.clear).frame(minHeight: 100)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
    }

    // MARK: - Renovations

    var renovationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RENOVATIONS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35))
                Spacer()
                Button { withAnimation { showRenovationForm.toggle() } } label: {
                    Image(systemName: showRenovationForm ? "minus.circle.fill" : "plus.circle.fill")
                        .foregroundStyle(Color.accentColor).font(.system(size: 18))
                }.buttonStyle(.plain)
            }.padding(.leading, 4).padding(.top, 20)

            if !renovations.isEmpty {
                VStack(spacing: 0) {
                    ForEach(renovations) { r in
                        HStack(spacing: 10) {
                            Circle().fill(.blue).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title).font(.system(size: 14, weight: .medium))
                                Text(r.yearRange).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { renovations.removeAll { $0.id == r.id } } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Color.primary.opacity(0.3))
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        if r.id != renovations.last?.id {
                            Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 32)
                        }
                    }
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
            }

            if showRenovationForm {
                VStack(spacing: 8) {
                    formFieldGroup {
                        formFieldRow("wrench.fill", "Renovation title", $newRenTitle)
                        formDivider()
                        formFieldRow("calendar", "Start year", $newRenFrom, keyboard: .numberPad)
                        formDivider()
                        formFieldRow("calendar", "End year (optional)", $newRenTo, keyboard: .numberPad)
                    }
                    Button {
                        guard !newRenTitle.isEmpty, let from = Int(newRenFrom) else { return }
                        renovations.append(Renovation(yearFrom: from, yearTo: Int(newRenTo), title: newRenTitle))
                        newRenTitle = ""; newRenFrom = ""; newRenTo = ""; showRenovationForm = false
                    } label: {
                        Text("Add renovation").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(newRenTitle.isEmpty || newRenFrom.isEmpty ? Color.primary.opacity(0.3) : .blue)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }.buttonStyle(.plain).disabled(newRenTitle.isEmpty || newRenFrom.isEmpty)
                }
            }
        }
    }

    // MARK: - Owners

    var ownersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("OWNERS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35))
                Spacer()
                Button { withAnimation { showOwnerForm.toggle() } } label: {
                    Image(systemName: showOwnerForm ? "minus.circle.fill" : "plus.circle.fill")
                        .foregroundStyle(Color.accentColor).font(.system(size: 18))
                }.buttonStyle(.plain)
            }.padding(.leading, 4).padding(.top, 20)

            if !owners.isEmpty {
                VStack(spacing: 0) {
                    ForEach(owners) { o in
                        HStack(spacing: 10) {
                            Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.4)).frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(o.name).font(.system(size: 14, weight: .medium))
                                Text(o.yearRange).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { owners.removeAll { $0.id == o.id } } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Color.primary.opacity(0.3))
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        if o.id != owners.last?.id {
                            Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 40)
                        }
                    }
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
            }

            if showOwnerForm {
                VStack(spacing: 8) {
                    formFieldGroup {
                        formFieldRow("person.fill", "Owner name", $newOwnerName)
                        formDivider()
                        formFieldRow("calendar", "Start year", $newOwnerFrom, keyboard: .numberPad)
                        formDivider()
                        formFieldRow("calendar", "End year (optional)", $newOwnerTo, keyboard: .numberPad)
                    }
                    Button {
                        guard !newOwnerName.isEmpty, let from = Int(newOwnerFrom) else { return }
                        owners.append(OwnerRecord(name: newOwnerName, yearFrom: from, yearTo: Int(newOwnerTo)))
                        newOwnerName = ""; newOwnerFrom = ""; newOwnerTo = ""; showOwnerForm = false
                    } label: {
                        Text("Add owner").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(newOwnerName.isEmpty || newOwnerFrom.isEmpty ? Color.primary.opacity(0.3) : .blue)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }.buttonStyle(.plain).disabled(newOwnerName.isEmpty || newOwnerFrom.isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    func save() async {
        isSaving = true; defer { isSaving = false }
        var updated = property
        updated.name = name; updated.addressLine1 = addressLine1; updated.city = city
        updated.country = country; updated.propertyType = propertyType
        updated.postalCode = postalCode.isEmpty ? nil : postalCode
        updated.sizeSqm = Double(sizeSqmText); updated.numRooms = Int(numRoomsText)
        updated.latitude = latitude; updated.longitude = longitude
        updated.yearBuilt = Int(yearBuiltText)
        updated.story = story.isEmpty ? nil : story
        updated.renovations = renovations; updated.owners = owners
        await onSave(updated); HapticFeedback.success(); dismiss()
    }

    private func reverseGeocode() async {
        guard let lat = latitude, let lon = longitude else { return }
        if let p = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)).first {
            if let t = p.thoroughfare { addressLine1 = t + (p.subThoroughfare.map { " " + $0 } ?? "") }
            if let l = p.locality { city = l }
            if let pc = p.postalCode, !pc.isEmpty { postalCode = pc }
            if let cc = p.isoCountryCode { country = cc }
        }
    }

    private func useCurrentLocation() async {
        isLocating = true; defer { isLocating = false }
        let mgr = CLLocationManager()
        mgr.requestWhenInUseAuthorization()
        if let loc = mgr.location {
            latitude = loc.coordinate.latitude; longitude = loc.coordinate.longitude
            mapPosition = .region(MKCoordinateRegion(center: loc.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
            if !showMap { showMap = true }
            await reverseGeocode()
        }
    }

    private func applyManualCoords() {
        guard let lat = Double(latText.replacingOccurrences(of: ",", with: ".")),
              let lon = Double(lonText.replacingOccurrences(of: ",", with: ".")) else { return }
        latitude = lat; longitude = lon
        mapPosition = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon), span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
        if !showMap { showMap = true }
    }
}
