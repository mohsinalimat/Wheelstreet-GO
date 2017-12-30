//
//  HomeViewController.swift
//  Wheelstreet
//
//  Created by JOGENDRA on 05/12/17.
//  Copyright © 2017 Kush Taneja. All rights reserved.
//

import UIKit
import GooglePlaces
import GoogleMaps
import Alamofire

fileprivate struct Defaults {
  static let wsLatitude = 12.9382828
  static let wsLongitude = 77.6237627
  static let zoomLevel: Float = 16.0
}

protocol HomeStatusBarDelegate: class {
  func didChangeUserStatus(homeUserStatus: UserStatus)
}

class HomeViewController: UIViewController, UINavigationControllerDelegate {

  var goMapView: GoMapView?

  var selectedPlace: GMSPlace?

  var locationManager = CLLocationManager()

  var currentLocation: CLLocation?

  var didFindMyLocation = false

  var goPullUpView: GoPullUpView = {
    if let view = Bundle.main.loadNibNamed("GoPullUpView", owner: self, options: nil)?.first as? GoPullUpView {
      return view
    }
    else {
      fatalError("Unable to Load GoPullUpView from nib")
    }
  }()

//  var statusBarView = Bundle.main.loadNibNamed("StatusBarView", owner: self, options: nil)?.first as? StatusBarView

  let defaultLocation: CLLocation = CLLocation(latitude: Defaults.wsLatitude, longitude: Defaults.wsLongitude)

  var userProfileView = Bundle.main.loadNibNamed("UserProfileView", owner: self, options: nil)?.first as? UserProfileView

  var userAuthStatus: UserStatus?

  var isPullViewPresented: Bool = false

  let refreshButton = GoButtons.refreshButton

  let unlockButton = GoButtons.unlockButton

  let userButton = GoButtons.userButton
    
  let helpButton = GoButtons.helpButton

  let customerCareButton = GoButtons.customerCareButton

  let customMyLocationButton = GoButtons.customMyLocationButton

  var path = GMSMutablePath()

  let polyline = GMSPolyline()

  var scannedViewController: ScannerViewController?

  weak var homeStatusBarDelegate: HomeStatusBarDelegate?

  var blurLayer: UIView = UIView(frame: CGRect.zero)

  var goBikes: [GoBike]!
  
  init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?, bikes: [GoBike]?) {
    super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

    if let bikes = bikes {
      self.goBikes = bikes
    }
    else {
      self.getAllBikeLocation()
    }
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    self.navigationController?.isNavigationBarHidden = true
    addMapView()

    WheelstreetAPI.checkUser()
    setupLayoutForButtons()
    customMyLocationButton.addTarget(self, action: #selector(goToMyCurrentLocation(_:)), for: .touchUpInside)
    addPullUpView()
    addTargetsToButtons()
    if (goBikes) != nil {
      setMarkerToBikes()
    }
    addBlurViewLayer()
    blurView(isHidden: true)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    UIApplication.makeNavigationBarTransparent(statusBarStyle: .default)
  }

  fileprivate func setMarkerToBikes() {
    for bike in goBikes {
      self.markBikePlace(latitude: (bike.location?.latitude)!, langitude: (bike.location?.longitude)!)
    }
  }


  func addTargetsToButtons() {
    refreshButton.addTarget(self, action: #selector(refreshButtonTapped(_:)), for: .touchUpInside)
    unlockButton.addTarget(self, action: #selector(didTapUnlock), for: .touchUpInside)

    customMyLocationButton.addTarget(self, action: #selector(goToMyCurrentLocation(_:)), for: .touchUpInside)
    userButton.addTarget(self, action: #selector(didTapUserButton), for: .touchUpInside)
    customerCareButton.addTarget(self, action: #selector(didTapCallCustomerCare(_:)), for: .touchUpInside)
  }


  @objc func didTapUnlock() {
    UIApplication.navigationController().pushViewController(UIStoryboard.scannerVC(), animated: true)
  }

  func didTapUnlockFor(bike: GoBike) {
    let scannerVC = UIStoryboard.scannerVC() as? ScannerViewController
    scannerVC?.tappedBike = bike
    UIApplication.navigationController().pushViewController(scannerVC!, animated: true)
  }
    @objc func didTapCallCustomerCare(_ sender: Any) {
      WheelstreetCommon.help()
    }

  @objc func didTapUserButton() {
   userButtonTapped()
  }

  func userButtonTapped() {
    if UserDefaults.standard.bool(forKey: GoKeys.isUserLoggedIn) {
        blurView(isHidden: false)
        guard let userProfileView = userProfileView else {
            return
        }
        userProfileView.userProfileDelegate = self
        userProfileView.frame = CGRect(x: 0, y: 0, width: self.view.frame.width, height: self.view.frame.height)
        userProfileView.layer.opacity = 0.0
        blurLayer.layer.opacity = 0.0
        
        UIView.animate(withDuration: 0.2, animations: {
            userProfileView.frame = CGRect(x: 0, y: 0, width: self.view.frame.width, height: self.view.frame.height - 66.0)
            self.blurLayer.addSubview(userProfileView)
            userProfileView.layer.opacity = 0.4
            self.blurLayer.layer.opacity = 0.4
        }, completion: { (true) in
                userProfileView.layer.opacity = 1.0
                self.blurLayer.layer.opacity = 1.0
                userProfileView.layer.cornerRadius = 0.0
            })
      } else {
      let splashScreen = UIStoryboard.splashNavigationScreen()
      let appDelegate = UIApplication.shared.delegate as! AppDelegate
      appDelegate.navigationController = UINavigationController(rootViewController: splashScreen)
      UIApplication.topViewController()!.present( UIApplication.navigationController(), animated: true, completion: nil)
    }
  }

  func addBlurViewLayer() {
    blurLayer = UIView(frame: CGRect(x: 0, y: 0, width: self.view.frame.width, height: self.view.frame.height + 80))
    let blurEffect = UIBlurEffect(style: UIBlurEffectStyle.regular)
    let visualEffectView = UIVisualEffectView(effect: blurEffect)
    blurLayer.frame = CGRect(x: 0, y: 0, width: blurLayer.frame.width, height: blurLayer.frame.height)
    visualEffectView.frame = blurLayer.frame
    blurLayer.addSubview(visualEffectView)
    self.view.insertSubview(blurLayer, belowSubview: self.userButton)
  }

  func blurView(isHidden: Bool) {
    blurLayer.isHidden = isHidden
    goButtonsHidden(isHide: !isHidden)
  }

  func addMapView() {
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    locationManager.requestAlwaysAuthorization()
    locationManager.distanceFilter = 50
    locationManager.delegate = self
    locationManager.startUpdatingLocation()

    let defaultCamera = GMSCameraPosition.camera(withLatitude: Defaults.wsLatitude, longitude: Defaults.wsLongitude, zoom: Defaults.zoomLevel)

    goMapView = GoMapView(frame: view.frame, goCamera: defaultCamera)

//    goMapView?.addObserver(self, forKeyPath: "myLocation", options: NSKeyValueObservingOptions.new, context: nil)

    goMapView?.settings.myLocationButton = false
    goMapView?.settings.compassButton = true
    goMapView?.goDelegate = self
    goMapView?.animate(toZoom: Defaults.zoomLevel)


    let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: Defaults.wsLatitude, longitude: Defaults.wsLongitude))
    marker.icon =  UIImage(named: GoImages.goMarkerIcon)

    guard let goMapView = goMapView else {
      return
    }

    goMapView.isMyLocationEnabled = true

    view.addSubview(goMapView)
    goMapView.translatesAutoresizingMaskIntoConstraints = false
    goMapView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    goMapView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
    goMapView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
    goMapView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true

    guard let currentLocation = goMapView.myLocation else {
      return
    }

    let updatedCamera = GMSCameraUpdate.setTarget(currentLocation.coordinate, zoom: Defaults.zoomLevel)
    goMapView.moveCamera(updatedCamera)

    marker.position = currentLocation.coordinate
    marker.map = goMapView
    marker.icon =  UIImage(named: GoImages.goMarkerIcon)
  }

  fileprivate func getAllBikeLocation() {
    WheelstreetAPI.getAllBikeLocation(completion: { goBikes, statusCode in
      guard let goBikes = goBikes else {
        return
      }
      self.goBikes = goBikes
      for bike in goBikes {
        self.markBikePlace(latitude: (bike.location?.latitude)!, langitude: (bike.location?.longitude)!)
      }
    })
  }

  fileprivate func markBikePlace(latitude: Double, langitude: Double) {
    let marker = GMSMarker()
    marker.position = CLLocationCoordinate2D(latitude: latitude, longitude: langitude)
    marker.icon =  UIImage(named: GoImages.goMarkerIcon)
    marker.map = goMapView
  }

//  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
//    if !didFindMyLocation {
//      let myLocation: CLLocation = change![NSKeyValueChangeKey.newKey] as! CLLocation
//      self.goMapView?.camera = GMSCameraPosition.camera(withTarget: myLocation.coordinate, zoom: Defaults.zoomLevel)
//      didFindMyLocation = true
//    }
//  }

  func setupLayoutForButtons() {

    // User Button setup
    view.addSubview(userButton)
    userButton.translatesAutoresizingMaskIntoConstraints = false
    userButton.topAnchor.constraint(equalTo: view.topAnchor, constant: GoButtons.userbuttonTopAnchorConstant).isActive = true
    userButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: GoButtons.userButtonLeadingAnchorConstant).isActive = true
    userButton.heightAnchor.constraint(equalToConstant: GoButtons.userButtonHeight).isActive = true
    userButton.widthAnchor.constraint(equalToConstant: GoButtons.userButtonWidth).isActive = true

    // Help Buttuon setup
    view.addSubview(helpButton)
    helpButton.translatesAutoresizingMaskIntoConstraints = false
    helpButton.centerYAnchor.constraint(equalTo: userButton.centerYAnchor).isActive = true
    helpButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -GoButtons.userButtonLeadingAnchorConstant).isActive = true
    helpButton.heightAnchor.constraint(equalTo: userButton.heightAnchor).isActive = true
    helpButton.widthAnchor.constraint(equalTo: userButton.widthAnchor).isActive = true

    // Customer Service Button setup
    view.addSubview(customerCareButton)
    customerCareButton.translatesAutoresizingMaskIntoConstraints = false
    customerCareButton.centerXAnchor.constraint(equalTo: userButton.centerXAnchor).isActive = true
    customerCareButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: GoButtons.customerCareButtonBottomAnchorConstant).isActive = true
    customerCareButton.heightAnchor.constraint(equalTo: userButton.heightAnchor).isActive = true
    customerCareButton.widthAnchor.constraint(equalTo: userButton.widthAnchor).isActive = true

    // Refresh Button setup
    view.addSubview(refreshButton)
    self.refreshButton.translatesAutoresizingMaskIntoConstraints = false
    self.refreshButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -GoButtons.userButtonLeadingAnchorConstant).isActive = true
    self.refreshButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: GoButtons.refreshButtonBottomAnchorConstant).isActive = true
    self.refreshButton.heightAnchor.constraint(equalTo: userButton.heightAnchor).isActive = true
    self.refreshButton.widthAnchor.constraint(equalTo: userButton.widthAnchor).isActive = true

    // Unlock Button setup
    view.addSubview(unlockButton)
    self.unlockButton.translatesAutoresizingMaskIntoConstraints = false
    self.unlockButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
    self.unlockButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: GoButtons.customerCareButtonBottomAnchorConstant).isActive = true
    self.unlockButton.heightAnchor.constraint(equalToConstant: GoButtons.unlockButtonHeight).isActive = true
    self.unlockButton.widthAnchor.constraint(equalToConstant: GoButtons.unlockButtonWidth).isActive = true

    // Custom My Location Button setup
    view.addSubview(customMyLocationButton)
    self.customMyLocationButton.translatesAutoresizingMaskIntoConstraints = false
    self.customMyLocationButton.centerYAnchor.constraint(equalTo: customerCareButton.centerYAnchor).isActive = true
    self.customMyLocationButton.centerXAnchor.constraint(equalTo: helpButton.centerXAnchor).isActive = true
    self.customMyLocationButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: GoButtons.customerCareButtonBottomAnchorConstant).isActive = true
  }


  fileprivate func addPullUpView() {
    goPullUpView.frame = CGRect(x: 8.0, y: view.frame.height - 183 - 8.0, width: view.frame.width - 16.0, height: 183)
    view.addSubview(goPullUpView)
    addConstraintsToPullUpView()
    goPullUpView.pullViewDelegate = self
    goPullUpView.isHidden = true
  }
    
    func addConstraintsToPullUpView() {
        goPullUpView.translatesAutoresizingMaskIntoConstraints = false
        goPullUpView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8.0).isActive = true
        goPullUpView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8.0).isActive = true
        goPullUpView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8.0).isActive = true
        goPullUpView.heightAnchor.constraint(equalToConstant: 183.0).isActive = true
    }

  fileprivate func updatePullUpView(present: Bool, bike: GoBike? = nil) {
    goPullUpView.isHidden = !present

    if let bike = bike {
      goPullUpView.bike = bike
    }
    // Remove the previous drawed line
    polyline.map = nil
    // Add pull view to map
    goPullUpView.frame = CGRect(x: 8.0, y: view.frame.height - 183 - 8.0, width: view.frame.width - 16.0, height: 183)
    goPullUpView.transform = CGAffineTransform(translationX:0, y: present ? goPullUpView.bounds.height : 2*goPullUpView.bounds.height)

    
    
    GoPullUpView.animate(withDuration: 0.3, animations: {
      self.goPullUpView.translatesAutoresizingMaskIntoConstraints = true
      self.goPullUpView.transform = CGAffineTransform.identity
      self.addConstraintsToPullUpView()
      GoButtons.customerCareButton.isHidden = present
      self.unlockButton.isHidden = present
      self.refreshButton.isHidden = present
      self.customMyLocationButton.isHidden = present
    }, completion: { (cancelled) in
      self.isPullViewPresented = present
    })
  }

  @objc func refreshButtonTapped(_ sender: Any) {
    let myLoactionCamera = GMSCameraPosition.camera(withTarget: defaultLocation.coordinate, zoom: Defaults.zoomLevel)
    let updatedCamera = GMSCameraUpdate.setTarget(defaultLocation.coordinate, zoom: Defaults.zoomLevel)
    goMapView?.camera = myLoactionCamera
    goMapView?.animate(to: myLoactionCamera)
    goMapView?.moveCamera(updatedCamera)
  }

  @objc func goToMyCurrentLocation(_ sender: Any) {
    guard let lat = self.goMapView?.myLocation?.coordinate.latitude,
      let lng = self.goMapView?.myLocation?.coordinate.longitude else { return }

    let camera = GMSCameraPosition.camera(withLatitude: lat ,longitude: lng , zoom: Defaults.zoomLevel)
    self.goMapView?.animate(to: camera)
  }
    
    func goButtonsHidden(isHide: Bool) {
        self.userButton.isHidden = isHide
        self.helpButton.isHidden = isHide
        self.refreshButton.isHidden = isHide
        self.customMyLocationButton.isHidden = isHide
    }

}


extension HomeViewController: CLLocationManagerDelegate {

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {

    guard let goMapView = goMapView, let currentLocation = locations.last else {
      return
    }

    self.currentLocation = currentLocation

    let currentLocationCamera = GMSCameraPosition.camera(
      withLatitude: currentLocation.coordinate.latitude,
      longitude: currentLocation.coordinate.longitude,
      zoom: Defaults.zoomLevel)

    goMapView.camera = currentLocationCamera
    goMapView.animate(to: currentLocationCamera)

  }

}


extension HomeViewController: GoMapViewDelegate {

  func didTapMarker(_ mapView: GMSMapView, didTap marker: GMSMarker) {
    let tappedPosition = marker.position
    let tappedLatitude = tappedPosition.latitude

    let filteredBike = goBikes.filter { $0.location?.latitude == tappedLatitude }

    if filteredBike.count > 0 {
      updatePullUpView(present: true, bike: filteredBike[0])
    }
    let tappedBikeLocation = CLLocation(latitude: (filteredBike[0].location?.latitude)!, longitude: (filteredBike[0].location?.longitude)!)

    drawPath(destinationLocation: tappedBikeLocation)
  }

  func didTapOnMap(_ mapView: GMSMapView) {
    updatePullUpView(present: false)
  }

  func drawPath(destinationLocation: CLLocation) {
    let originLocation = CLLocation(latitude: Defaults.wsLatitude, longitude: Defaults.wsLongitude)
    let origin = "\(originLocation.coordinate.latitude),\(originLocation.coordinate.longitude)"
    let destination = "\(destinationLocation.coordinate.latitude),\(destinationLocation.coordinate.longitude)"

    let url = "https://maps.googleapis.com/maps/api/directions/json?origin=\(origin)&destination=\(destination)&mode=walking"

    Alamofire.request(url).responseJSON { response in

      let json = JSON(data: response.data!)
      let routes = json["routes"].arrayValue

      for route in routes
      {
        let routeOverviewPolyline = route["overview_polyline"].dictionary
        let points = routeOverviewPolyline?["points"]?.stringValue
        let path = GMSPath.init(fromEncodedPath: points!)
        self.polyline.path = path
        self.polyline.strokeColor = UIColor(red: 25.0/255.0, green: 206.0/255.0, blue: 145.0/255.0, alpha: 1.0)
        self.polyline.strokeWidth = 5.0
        self.polyline.map = self.goMapView
      }
      }.resume()
  }
}


extension HomeViewController: UserProfileDelegate {
    func didTapSignOut() {
        self.goButtonsHidden(isHide: false)
        self.userProfileView?.removeFromSuperview()
        self.blurView(isHidden: true)
    }
    
  func didTapMapButton() {
    self.userProfileView?.removeFromSuperview()
    self.blurView(isHidden: true)
    self.view.setNeedsDisplay()
    self.goButtonsHidden(isHide: false)
  }
}

extension HomeViewController: GoPullUpViewDelegate {
  func presentFareDetailsFor(bike: GoBike) {
    let fareDetailsVC = FareDetailsViewController(nibName: "FareDetailsViewController", bundle: nil, bike: bike)
  
    UIApplication.topViewController()?.present(fareDetailsVC, animated: true, completion: nil)
  }

  func didTapUnlockButtonFor(bike: GoBike) {
    self.didTapUnlockFor(bike: bike)
  }


}