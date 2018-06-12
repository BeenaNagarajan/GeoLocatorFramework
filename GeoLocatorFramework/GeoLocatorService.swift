//
//  GeoLocatorService.swift
//  GeoLocatorFramework
//
//  Created by Bayer iMac Onyx on 29/05/18.
//  Copyright © 2018 wipro. All rights reserved.
//

import Foundation
import CoreLocation
import SystemConfiguration

//extension Notification.Name {
//     static let locationUpdated = Notification.Name("locationUpdated")
//}
//public protocol geoLocationDelegate: AnyObject {
//    func didReceiveLatAndLong(sender: GeoLocatorService, location: String)
//}


enum locationStatus: Int {
    case success = 1
    case denied = 2
    case serviceDisabled = 3
    case locationUnavailable = 4
    case addressUnavailable = 5
    case unknown = 6
}
enum requestType: Int {
    case location = 1
    case address = 2
}
//MARK: Network Reachability
protocol Utilities {
}

extension NSObject:Utilities{
    
    enum ReachabilityStatus: String {
        case notReachable = "notReachable"
        case reachableViaGPS = "reachableViaGPS"
        case reachableViaWWAN = "reachableViaWWAN"
        case reachableViaWiFi = "reachableViaWiFi"
    }
    
    /* To get the current network provider to get the location details */
    var currentReachabilityStatus: ReachabilityStatus {
        
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        guard let defaultRouteReachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else {
            return .notReachable
        }
        
        var flags: SCNetworkReachabilityFlags = []
        if !SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags) {
            return .notReachable
        }
        
        if flags.contains(.reachable) == false {
            // The target host is not reachable.
            return .reachableViaGPS
        }
        else if flags.contains(.isWWAN) == true {
            // WWAN connections are OK if the calling application is using the CFNetwork APIs.
            return .reachableViaWWAN
        }
        else if flags.contains(.connectionRequired) == false {
            // If the target host is reachable and no connection is required then we'll assume that you're on Wi-Fi...
            return .reachableViaWiFi
        }
        else if (flags.contains(.connectionOnDemand) == true || flags.contains(.connectionOnTraffic) == true) && flags.contains(.interventionRequired) == false {
            // The connection is on-demand (or on-traffic) if the calling application is using the CFSocketStream or higher APIs and no [user] intervention is needed
            return .reachableViaWiFi
        }
        else {
            return .notReachable
        }
    }
}

public class GeoLocatorService:NSObject, CLLocationManagerDelegate {
    var didFindLocation: Bool!
    var locationManager:CLLocationManager!
    var locationReqID: String! = ""
    //    public weak var geoDelegate: geoLocationDelegate?
    @objc static public var didReceiveLocation: ((_ result: String)->())? //an optional function
    
    @objc func locationAccessibleStatus()-> Int {
        
        if CLLocationManager.locationServicesEnabled() {
            switch CLLocationManager.authorizationStatus() {
            case .authorizedAlways, .authorizedWhenInUse:
                print("User granted the access")
                return locationStatus.success.rawValue
                
            case .notDetermined, .restricted, .denied:
                print("User denied the access")
                return locationStatus.denied.rawValue
            }
        }
        else {
            print("Location services are disabled")
            return locationStatus.serviceDisabled.rawValue
        }
    }
    public override init() {
        super.init()
        setupConfiguration()
    }
    
    @objc func setupConfiguration () {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        didFindLocation = false
        //        locationManager.requestWhenInUseAuthorization()
        locationManager.requestAlwaysAuthorization()
        if #available(iOS 9.0, *) {
        locationManager.allowsBackgroundLocationUpdates = true
        }
    }
    
    //MARK: Get current location
    @objc public func getLocation(reqID: String){
        var jsonString: String!
        var jsonDict = [String: Any]()
        locationReqID = reqID
        jsonDict["reqID"] = locationReqID
        jsonDict["reqType"] = requestType.location.rawValue
        didFindLocation = false
        
        if currentReachabilityStatus != ReachabilityStatus.notReachable {
            jsonDict["provider"] = currentReachabilityStatus.rawValue
            let locationAccessibilityStatus = locationAccessibleStatus()
            if (locationAccessibilityStatus == locationStatus.serviceDisabled.rawValue || locationAccessibilityStatus == locationStatus.denied.rawValue || locationAccessibilityStatus == locationStatus.unknown.rawValue) {
                jsonDict["status"] = locationAccessibilityStatus
                jsonString = createJSONResponse(dict: jsonDict as NSDictionary)
                GeoLocatorService.didReceiveLocation?(_: jsonString!)
            } else if locationAccessibilityStatus == locationStatus.success.rawValue {
                locationManager.startUpdatingLocation()
                locationManager.startMonitoringSignificantLocationChanges()
            }
        }
    }
    
    //MARK: Create JSON response
    @objc func createJSONResponse(dict: NSDictionary) -> String {
        let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [])
        let jsonString = String(data: jsonData!, encoding: .utf8)
        //        print("\(jsonString!)\n======================")
        return jsonString!
    }
    
    //MARK: Get address for location
    @objc public func getAddressWithReqID(reqID:String, forLat:Double, andLong: Double, withCompletionHandler:@escaping (String) -> Void) {
        var center : CLLocationCoordinate2D = CLLocationCoordinate2D()
        let ceo: CLGeocoder = CLGeocoder()
        center.latitude = forLat
        center.longitude = andLong
        
        //        center.latitude = 17.34342343
        //        center.longitude = 78.32423423
        let loc: CLLocation = CLLocation(latitude:center.latitude, longitude: center.longitude)
        
        ceo.reverseGeocodeLocation(loc, completionHandler:
            {(placemarks, error) in
                if (error != nil)
                {
                    print("reverse geodcode fail: \(error!.localizedDescription)\n======================")
                    withCompletionHandler(error!.localizedDescription)
                }
                else {
                    let pm = placemarks! as [CLPlacemark]
                    
                    if pm.count > 0 {
                        let pm = placemarks![0]
                        var addressString : String = ""
                        if pm.subLocality != nil {
                            addressString = addressString + pm.subLocality!
                        }
                        if pm.thoroughfare != nil {
                            addressString = addressString + ", " + pm.thoroughfare!
                        }
                        if pm.locality != nil {
                            addressString = addressString + ", " + pm.locality!
                        }
                        if pm.country != nil {
                            addressString = addressString + ", " + pm.country!
                        }
                        if pm.postalCode != nil {
                            addressString = addressString + ", " + pm.postalCode! + " "
                        }
                        if pm.subLocality == nil && pm.thoroughfare == nil && pm.locality == nil && pm.country == nil && pm.postalCode == nil {
                            addressString = pm.addressDictionary!["Name"] as! String
                        }
                        let addressDict:[String: Any] = ["reqID": reqID, "reqType": requestType.address.rawValue, "status": 1, "address": addressString, "provider": self.currentReachabilityStatus.rawValue]
                        let address = self.createJSONResponse(dict: addressDict as NSDictionary)
                        print("Address in getAddressWithReqID: \(address)\n======================")
                        
                        withCompletionHandler(address)
                    }
                }
        })
    }
    
    //MARK: Location delegates
    
    //to provide current location updates
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        // Call stopUpdatingLocation() to stop listening for location updates,
        // other wise this function will be called every time when user location changes.
        if !didFindLocation {
            didFindLocation = true
            manager.stopUpdatingLocation()
            //            manager.pausesLocationUpdatesAutomatically = true
            let userLocation:CLLocation = locations[0] as CLLocation
            let locationLat = userLocation.coordinate.latitude
            let locationLong = userLocation.coordinate.longitude
            let altitude = userLocation.altitude
            let horizontalAccuracy = userLocation.horizontalAccuracy
            print("updated latitude = \(locationLat)")
            print("updated longitude = \(locationLong)")
            print("updated altitude = \(altitude)")
            print("updated horizontalAccuracy = \(horizontalAccuracy)\n======================")
            let locationDict:[String: Any] = ["reqID": locationReqID, "reqType": requestType.location.rawValue, "status": locationStatus.success.rawValue, "latitude": locationLat, "longitude": locationLong, "accuracy": horizontalAccuracy, "provider": currentReachabilityStatus.rawValue]
            let locationString = createJSONResponse(dict: locationDict as NSDictionary)
            print("location in didUpdateLocations: \(locationString)\n======================")
            //            geoDelegate?.didReceiveLatAndLong(sender: self, location: locationString)
            GeoLocatorService.didReceiveLocation?(_: locationString)
            
            
            //            NotificationCenter.default.post(name: NSNotification.Name("locationUpdated"), object: nil, userInfo: locationDict)
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error)
    {
        print("=============\nError code \(error)")
        print("Error message \(error.localizedDescription)")
        let locationDict:[String: Any] = ["reqID": locationReqID, "reqType": requestType.location.rawValue, "status": locationStatus.locationUnavailable.rawValue, "provider": currentReachabilityStatus.rawValue]
        let locationString = createJSONResponse(dict: locationDict as NSDictionary)
        print("location in didUpdateLocations: \(locationString)\n======================")
        //            geoDelegate?.didReceiveLatAndLong(sender: self, location: locationString)
        GeoLocatorService.didReceiveLocation?(_: locationString)
    }
    
    public func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        print("Visit: \(visit)")
        // I find that sending this to a UILocalNotification is handy for debugging
    }
    
//    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
//        switch status {
//        case .notDetermined:
//            locationManager.requestAlwaysAuthorization()
//            break
//        case .authorizedWhenInUse:
//            locationManager.startUpdatingLocation()
//            break
//        case .authorizedAlways:
//            locationManager.startUpdatingLocation()
//            break
//        case .restricted:
//            // restricted by e.g. parental controls. User can't enable Location Services
//            break
//        case .denied:
//            // user denied your app access to Location Services, but can grant access from Settings.app
//            break
//        default:
//            break
//        }
//    }
}
