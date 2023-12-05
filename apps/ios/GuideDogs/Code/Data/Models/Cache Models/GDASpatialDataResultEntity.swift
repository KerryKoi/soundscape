//
//  GDASpatialDataResultEntity.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation
import CoreLocation
import RealmSwift

class LocalizedString: Object {
    /// Lowercase ISO 639-1 alpha2 code (second column), or a lowercase ISO 639-2 code if an ISO 639-1 code doesn't exist.
    /// http://www.loc.gov/standards/iso639-2/php/code_list.php
    @objc dynamic var language: String = ""
    @objc dynamic var string: String = ""

    convenience init(language: String, string: String) {
        self.init()
    
        self.language = language
        self.string = string
    }
}

class GDASpatialDataResultEntity: Object {
    
    // MARK: - Realm properties
    
    @objc dynamic var key: String = UUID().uuidString
    @objc dynamic var lastSelectedDate: Date?
    /// The default entity name
    @objc dynamic var name: String = ""
    /// Array of localized entity names. e.g. `["en": "Louvre Museum", "fr": "Musée du Louvre"]`
    let names = List<LocalizedString>()
    /// For some OSM entities (i.e. "Road", "Walking Path" and "Bus stop")
    /// we also store the type (i.e, "road", "walking_path", "bus_stop")
    /// so we can localize and display the name correctly.
    @objc dynamic var nameTag: String = ""
    /// "ref" stands for "reference" and is used for reference numbers or codes.
    /// Common for roads, highway exits, routes, etc. It is also used for shops and amenities
    /// that are numbered officially as part of a retail brand or network respectively.
    /// - note: https://wiki.openstreetmap.org/wiki/Key:ref
    @objc dynamic var ref: String = ""
    @objc dynamic var superCategory: String = SuperCategory.undefined.rawValue
    @objc dynamic var amenity: String!
    @objc dynamic var phone: String?
    @objc dynamic var addressLine: String?
    @objc dynamic var streetName: String?
    @objc dynamic var roundabout: Bool = false
    @objc dynamic var coordinatesJson: String?
    @objc dynamic var entrancesJson: String?
    @objc dynamic var dynamicURL: String?
    @objc dynamic var dynamicData: String?
    @objc dynamic var latitude: CLLocationDegrees = 0.0
    @objc dynamic var longitude: CLLocationDegrees = 0.0
    @objc dynamic var centroidLatitude: CLLocationDegrees = 0.0
    @objc dynamic var centroidLongitude: CLLocationDegrees = 0.0
    
    // MARK: - Computed & Non-Realm Properties
    
    private var _geometry: GeoJsonGeometry?
    var geometry: GeoJsonGeometry? {
        if _geometry != nil {
            return _geometry
        }
        // Otherwise, try to parse
        // TODO: we might want to store that we tried before and failed
        guard let geoJSON  = coordinatesJson else {
            return nil
        }
        _geometry = GeoJsonGeometry(geoJSON: geoJSON)
        return _geometry
    }
    
    var coordinates: Any? {
        return geometry?.coordinates
    }

    private var _entrances: [POI]?
    var entrances: [POI]? {
        if _entrances != nil {
            return _entrances
        }
        
        // Only POIs with non-point geometries can have entrances
        if case .point = geometry {
            return nil
        }
        guard coordinates != nil,
            let jsonData = entrancesJson?.data(using: .utf8) else {
            return nil
        }
        
        guard let entranceIDs = try? JSONSerialization.jsonObject(with: jsonData) as? [String] else {
            return nil
        }
        
        var entranceObjects = [POI]()
        for entranceID in entranceIDs {
            if let entrance = SpatialDataCache.searchByKey(key: entranceID) {
                entranceObjects.append(entrance)
            }
        }
        
        _entrances = entranceObjects
        
        return _entrances
    }
    
    // MARK: - Realm Related
    
    /// Indicates which property represents the primary key of this object
    override static func primaryKey() -> String {
        return "key"
    }
    
    /// Returns the names of properties which Realm should ignore
    static override func ignoredProperties() -> [String] {
        return ["_geometry",
                "geometry",
                "coordinates",
                "_entrances",
                "entrances"]
    }
    
    // MARK: - Initialization
    
    convenience init(id: String, parameters: LocationParameters) {
        self.init()
        
        key = id
        name = parameters.name
        self.latitude = parameters.coordinate.latitude
        self.longitude = parameters.coordinate.longitude
        centroidLatitude = parameters.coordinate.latitude
        centroidLongitude = parameters.coordinate.longitude
        superCategory = SuperCategory.undefined.rawValue
        amenity = ""
        addressLine = parameters.address
    }
    
    convenience init?(feature: GeoJsonFeature, key: String? = nil) {
        self.init()
        
        if let key = key {
            self.key = key
        } else if let firstId = feature.osmIds.first {
            self.key = firstId
        } else {
            return nil
        }
        
        guard !self.key.isEmpty else {
            return nil
        }
        
        superCategory = feature.superCategory.rawValue
        amenity = feature.value
        
        if let featureName = feature.name {
            name = featureName
        }
        
        if let localizedNames = feature.names, !localizedNames.isEmpty {
            for (language, name) in localizedNames {
                self.names.append(LocalizedString(language: language, string: name))
            }
        }
        
        if let nameTag = feature.nameTag, !nameTag.isEmpty {
            self.nameTag = nameTag
        }
        
        if let ref = feature.ref, !ref.isEmpty {
            self.ref = ref
        }
        
        // Set geolocation information
        if case .point(let point) = feature.geometry {
            latitude = point.latitude
            longitude = point.longitude
        } else if let json_data = try? JSONEncoder().encode(feature.geometry) {
            coordinatesJson = String(data: json_data, encoding: .utf8)
            _geometry = feature.geometry;
        }
        
        let centroid = feature.geometry.centroid
        centroidLatitude = centroid.latitude
        centroidLongitude = centroid.longitude
        
        // Road specific metadata
        
        roundabout = feature.isRoundabout
        
        // Set additional meta data
        
        if let dynamicURLProp = feature.properties["blind:website:en"] {
            dynamicURL = dynamicURLProp
        }
        
        if let phoneProp = feature.properties["phone"] {
            phone = phoneProp
        }
        
        if let streetNameProp = feature.properties["addr:street"] {
            streetName = streetNameProp
            
            if let streetNumProp = feature.properties["addr:housenumber"] {
                addressLine = streetNumProp + " " + streetNameProp
            }
        }
    }
    
    // MARK: - Geometries
    
    /// Returns whether a coordinate lies inside the entity.
    /// - note: This is only valid for entities that contain geometries with an area (polygons and multiPolygons), such as buildings.
    func contains(location: CLLocationCoordinate2D) -> Bool {
        guard let geometry = geometry else {
            return false
        }
        return geometry.withinArea(location)
    }
    
    // MARK: `NSObject`
    
    override var description: String {
        return "{\tName: \(name)\n\tID: \(key)"
    }
    
    // Adds the ability to show the location in Xcode's debug quick look (shown as a map with a marker)
    func debugQuickLookObject() -> AnyObject? {
        guard let userLocation = AppContext.shared.geolocationManager.location else {
            return nil
        }
        
        return self.closestLocation(from: userLocation)
    }
}
