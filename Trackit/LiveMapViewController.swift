//
//  GPXViewController.swift
//  Trackit
//
//  Created by CS193p Instructor.
//  Copyright © 2016 Stanford University. All rights reserved.
//

import UIKit
import MapKit
import CoreData

class DevicePolyLine : MKPolyline {
    var color : UIColor?
}

class RenderableDevice
{
    var pointsToUse: [CLLocationCoordinate2D] = []
    var polyline = DevicePolyLine()
    var device : Device

    var colorMap : [String : UIColor] = ["white" : UIColor.white,
                                         "red" : UIColor.red,
                                         "blue" : UIColor.blue,
                                         "green" : UIColor.green,
                                         "purple" : UIColor.purple,
                                         "orange" : UIColor.orange,
                                         "yellow" : UIColor.yellow,
                                         "magenta" : UIColor.magenta]
    
    init(device : Device) {
        self.device = device
    }

    func render(mapView : MKMapView) -> MKPolyline {
        // remove old one from map first
        if (polyline.pointCount > 0) {
            mapView.remove(polyline)
        }

        polyline = DevicePolyLine(coordinates: &pointsToUse, count: pointsToUse.count)
        if device.color != nil {
            polyline.color = colorMap[device.color!]
        } else {
            polyline.color = UIColor.red
        }

        print("adding polyline to view for \(pointsToUse.count) points")

        return polyline
    }

    func add(location: Location) {
        let latitude = location.latitude
        let longitude = location.longitude

        let p = CGPointFromString("{" + String(format: "%.9f", latitude) + "," + String(format: "%.9f", longitude) + "}")
        pointsToUse += [CLLocationCoordinate2DMake(CLLocationDegrees(p.x), CLLocationDegrees(p.y))]
    }
}

class RenderableRoute
{
    var devicesMap : [String : RenderableDevice] = [:]

}

class LiveMapViewController: UIViewController, MKMapViewDelegate, UIPopoverPresentationControllerDelegate
{
    var activeRoute : String = "default"

    func registerOverlays(isInitial : Bool) {
        for route in routes {
            for device in route.value.devicesMap {
                let overlay = device.value.render(mapView: mapView)
                mapView.add(overlay)
            }
        }
        adjustVisibleMapView(isInitial: isInitial)
    }

    func addToRoute(location: Location, route : String) {
        if routes[route] == nil {
            routes[route] = RenderableRoute()
        }

        if let renderedRoute = routes[route] {
            var deviceName : String

            if let device = location.device,
                let name = device.name {
                deviceName = name
            } else {
                deviceName = "mytracker-anemic"
            }

            if renderedRoute.devicesMap[deviceName] == nil {
                renderedRoute.devicesMap[deviceName] = RenderableDevice(device: location.device!)
            }

            if let renderedDevice = renderedRoute.devicesMap[deviceName] {
                renderedDevice.add(location: location)

                if renderedDevice.pointsToUse.count > 0 {
                    addWaypoint(coordinate: renderedDevice.pointsToUse.first!, name: "foo")
                }
            }
        }
    }

    func adjustVisibleMapView(isInitial : Bool) {
        // http://stackoverflow.com/questions/13569327/zoom-mkmapview-to-fit-polyline-points
        if let first = mapView.overlays.first {
            let rect = mapView.overlays.reduce(first.boundingMapRect, {MKMapRectUnion($0, $1.boundingMapRect)})
            mapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 50.0, left: 50.0, bottom: 50.0, right: 50.0), animated: isInitial)
        }
    }

    // MARK: Public Model

    @IBOutlet weak var menuButton: UIBarButtonItem!

    var routes : [String : RenderableRoute] = [:]

    var gpxURL: URL? {
        didSet {
            clearWaypoints()
            if let url = gpxURL {
                GPX.parse(url) { gpx in
                    if gpx != nil {
                        self.addWaypoints(gpx!.waypoints)
                    }
                }
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: View Controller Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        registerReveal(menuButton: menuButton)
        initializeVisibleRoutes(routes: ["frist"])

        let nc = NotificationCenter.default
        nc.addObserver(forName: (UIApplication.shared.delegate as! AppDelegate).dataIsStableNotification, object:nil, queue:nil, using:gpsDataIsStable)
        nc.addObserver(self, selector: #selector(managedObjectContextObjectsDidChange), name: NSNotification.Name.NSManagedObjectContextObjectsDidChange, object: coreDataContainer)
    }

    @IBOutlet weak var mapView: MKMapView! {
        didSet {
            mapView.mapType = .standard // .satellite
            mapView.delegate = self
        }
    }
    
    func initializeVisibleRoutes(routes: [String]) {
        for route in routes {
            coreDataContainer?.perform {
                print("loading route \(route)")
                let request = NSFetchRequest<Location>(entityName: "Location")
                let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
                request.sortDescriptors = [sortDescriptor]
                request.predicate = NSPredicate(format: "route.isVisible = true");

                if let results = try? self.coreDataContainer!.fetch(request) {
                    print("i see \(results.count) locations")
                    for location in results as [NSManagedObject] {
                        self.addToRoute(location: location as! Location, route: self.activeRoute)
                    }
                }
                DispatchQueue.main.async {
                    self.registerOverlays(isInitial: false)
                }
            }
        }
    }

    // MARK: Private Implementation

    fileprivate func clearWaypoints() {
        mapView?.removeAnnotations(mapView.annotations)
    }
    
    fileprivate func addWaypoints(_ waypoints: [GPX.Waypoint]) {
        mapView?.addAnnotations(waypoints)
        mapView?.showAnnotations(waypoints, animated: true)
    }
    
    fileprivate func selectWaypoint(_ waypoint: GPX.Waypoint?) {
        if waypoint != nil {
            mapView.selectAnnotation(waypoint!, animated: true)
        }
    }
    
    // MARK: MKMapViewDelegate

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        var view: MKAnnotationView! = mapView.dequeueReusableAnnotationView(withIdentifier: Constants.AnnotationViewReuseIdentifier)
        if view == nil {
            view = MKPinAnnotationView(annotation: annotation, reuseIdentifier: Constants.AnnotationViewReuseIdentifier)
            view.canShowCallout = true
        } else {
            view.annotation = annotation
        }
        
        view.isDraggable = annotation is EditableWaypoint
    
        view.leftCalloutAccessoryView = nil
        view.rightCalloutAccessoryView = nil
        if let waypoint = annotation as? GPX.Waypoint {
            if waypoint.thumbnailURL != nil {
                view.leftCalloutAccessoryView = UIButton(frame: Constants.LeftCalloutFrame)
            }
            if waypoint is EditableWaypoint {
                view.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            }
        }
        
        return view
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        if let thumbnailImageButton = view.leftCalloutAccessoryView as? UIButton,
            let url = (view.annotation as? GPX.Waypoint)?.thumbnailURL,
            let imageData = try? Data(contentsOf: url as URL), // blocks main queue
            let image = UIImage(data: imageData) {
            thumbnailImageButton.setImage(image, for: UIControlState())
        }
    }
    
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        if control == view.leftCalloutAccessoryView {
            performSegue(withIdentifier: Constants.ShowImageSegue, sender: view)
        } else if control == view.rightCalloutAccessoryView  {
            mapView.deselectAnnotation(view.annotation, animated: true)
            performSegue(withIdentifier: Constants.EditUserWaypoint, sender: view)
        }
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is MKPolyline {
            print("rendering for overlay \(overlay)")
            let lineView = MKPolylineRenderer(overlay: overlay)

            if let customOverlay = overlay as? DevicePolyLine {
                lineView.strokeColor = customOverlay.color
            }
            lineView.lineWidth = 1.0

            return lineView
        }
        return MKPolylineRenderer()
    }
    
    func managedObjectContextObjectsDidChange(notification: NSNotification) {
        guard let userInfo = notification.userInfo else { return }
        
        if let inserts = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>, inserts.count > 0 {
            for insert in inserts {
                // gps data inserted
                if let location = insert as? Location {
                    addToRoute(location: location, route: activeRoute)
                }
            }
        }

//        if let updates = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>, updates.count > 0 {
//            print("--- UPDATES ---")
//            for update in updates {
//                print(update.changedValues())
//            }
//            print("+++++++++++++++")
//        }
//        
//        if let deletes = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>, deletes.count > 0 {
//            print("--- DELETES ---")
//            print(deletes)
//            print("+++++++++++++++")
//        }
    }

    // MARK: Navigation
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let destination = segue.destination.contentViewController
        let annotationView = sender as? MKAnnotationView
        let waypoint = annotationView?.annotation as? GPX.Waypoint
        
        if segue.identifier == Constants.ShowImageSegue {
            if let ivc = destination as? ImageViewController {
                ivc.imageURL = waypoint?.imageURL
                ivc.title = waypoint?.name
            }
        } else if segue.identifier == Constants.EditUserWaypoint {
            if let editableWaypoint = waypoint as? EditableWaypoint,
                let ewvc = destination as? EditWaypointViewController {
                if let ppc = ewvc.popoverPresentationController {
                    ppc.sourceRect = annotationView!.frame
                    ppc.delegate = self
                }
                ewvc.waypointToEdit = editableWaypoint
            }
        } else if segue.identifier == Constants.MapSettings {
            if let msvc = destination as? MapSettingsViewController {
                msvc.mapView = mapView
                if let ppc = msvc.popoverPresentationController {
                    ppc.delegate = self
                }
            }
        }
    }

    func addWaypoint(coordinate: CLLocationCoordinate2D, name: String)
    {
            let waypoint = EditableWaypoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
            waypoint.name = name
            mapView.addAnnotation(waypoint)
    }
    
    // Long press gesture adds a waypoint

    @IBAction func addWaypoint(_ sender: UILongPressGestureRecognizer) {
        if sender.state == .began {
            let coordinate = mapView.convert(sender.location(in: mapView), toCoordinateFrom: mapView)
            addWaypoint(coordinate: coordinate, name: "Dropped")
        }
    }
    
    // Unwind target (selects just-edited waypoint)

    @IBAction func updatedUserWaypoint(_ segue: UIStoryboardSegue) {
        selectWaypoint((segue.source.contentViewController as? EditWaypointViewController)?.waypointToEdit)
    }
    
    // MARK: UIPopoverPresentationControllerDelegate
    
    // when popover is dismissed, selected the just-edited waypoint
    // see also unwind target above (does the same thing for adapted UI)

    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        selectWaypoint((popoverPresentationController.presentedViewController as? EditWaypointViewController)?.waypointToEdit)
    }
    
    // if we're horizontally compact
    // then adapt by going to .OverFullScreen
    // .OverFullScreen fills the whole screen, but lets underlying MVC show through

    func adaptivePresentationStyle(for controller: UIPresentationController,
                                   traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
    //    return traitCollection.horizontalSizeClass == .compact ? .overFullScreen : .none
        return traitCollection.horizontalSizeClass == .compact ? .none : .none
    }
    
    // when adapting to full screen
    // wrap the MVC in a navigation controller
    // and install a blurring visual effect behind all the navigation controller draws
    // autoresizingMask is "old style" constraints
    
    func presentationController(_ controller: UIPresentationController,
                                viewControllerForAdaptivePresentationStyle style: UIModalPresentationStyle
        ) -> UIViewController? {
        if style == .fullScreen || style == .overFullScreen {
            let navcon = UINavigationController(rootViewController: controller.presentedViewController)
            let visualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight))
            visualEffectView.frame = navcon.view.bounds
            visualEffectView.autoresizingMask = [.flexibleWidth,.flexibleHeight]
            navcon.view.insertSubview(visualEffectView, at: 0)
            return navcon
        } else {
            return nil
        }
    }
    
    // MARK: Constants
    
    fileprivate struct Constants {
        static let LeftCalloutFrame = CGRect(x: 0, y: 0, width: 59, height: 59) // sad face
        static let AnnotationViewReuseIdentifier = "waypoint"
        static let ShowImageSegue = "Show Image"
        static let EditUserWaypoint = "Edit Waypoint"
        static let MapSettings = "Map Settings"
    }

    func gpsDataIsStable(notification: Notification) -> Void {
        print("gpsDataIsStable")
        
        registerOverlays(isInitial : true)
    }
    

    var coreDataContainer : NSManagedObjectContext? =
        (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
    
}

extension UIViewController {
    var contentViewController: UIViewController {
        if let navcon = self as? UINavigationController {
            return navcon.visibleViewController ?? navcon
        } else {
            return self
        }
    }
    
    func registerReveal(menuButton: UIBarButtonItem) {
        if self.revealViewController() != nil {
            menuButton.target = self.revealViewController()
            menuButton.action = #selector(SWRevealViewController.revealToggle(_:))
            self.view.addGestureRecognizer(self.revealViewController().panGestureRecognizer())
            self.revealViewController().rearViewRevealWidth = 130
        }
    }
}


