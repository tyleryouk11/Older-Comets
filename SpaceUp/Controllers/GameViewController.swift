//
//  GameViewController.swift
//  SpaceUp
//
//  Created by David Chin on 2/06/2015.
//  Copyright (c) 2015 David Chin. All rights reserved.
//

import SpriteKit
import GameKit
import iAd
import StoreKit
import CoreMotion
import GoogleMobileAds

// TODO: Refactor, too many responsbilities atm
class GameViewController: UIViewController, GKGameCenterControllerDelegate, ADInterstitialAdDelegate, GameCenterManagerDelegate, GameSceneDelegate, StartSceneDelegate, SKProductsRequestDelegate, MotionDataSource {
  // MARK: - Immutable vars
  let gameCenterManager = GameCenterManager()
  let gameData = GameData.dataFromArchive()
  let motionManager = CMMotionManager()
  
  // MARK: - Vars
  //private var interstitialAdView: InterstitialAdView? //NOW
  private var interstitialAd: ADInterstitialAd?
  private var numberOfRetriesSinceLastAd: UInt = 0
  private var products: [SKProduct]?
  private var removeAdsProduct: SKProduct?

  // MARK: - Computed vars
  var skView: SKView! {
    return view as? SKView
  }
  
  // MARK: - View
  override func loadView() {
    super.loadView()

    view = SKView()
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    // iAd
    interstitialPresentationPolicy = .Manual
    
    // Configure the view.
    // skView.showsFPS = true
    // skView.showsNodeCount = true
    // skView.showsPhysics = true
    skView.ignoresSiblingOrder = true
    
    // Present scene
    preloadAndPresentStartScene()
    
    // Authenticate GameCenter in next loop
    dispatch_async(dispatch_get_main_queue()) {
      LoadingIndicatorView.sharedView.showInView(self.view)
      self.gameCenterManager.authenticateLocalPlayer()
    }
    
    // GameCenter
    gameCenterManager.delegate = self
  }
  
  override func viewWillAppear(animated: Bool) {
    // Motion
    observeMotion()
    
    // Notification
    let notificationCenter = NSNotificationCenter.defaultCenter()
    notificationCenter.addObserver(self, selector:"paymentTransactionDidComplete:" , name: PaymentTransactionDidRestoreNotification, object: nil)
    notificationCenter.addObserver(self, selector:"paymentTransactionDidRestore:" , name: PaymentTransactionDidRestoreNotification, object: nil)
    notificationCenter.addObserver(self, selector:"paymentTransactionDidFail:" , name: PaymentTransactionDidRestoreNotification, object: nil)
    notificationCenter.addObserver(self, selector:"applicationWillResignActive:", name: UIApplicationWillResignActiveNotification, object: nil)
    notificationCenter.addObserver(self, selector: "applicationDidBecomeActive:", name: UIApplicationDidBecomeActiveNotification, object: nil)
  }
  
  override func viewWillDisappear(animated: Bool) {
    let notificationCenter = NSNotificationCenter.defaultCenter()
    notificationCenter.removeObserver(self)
    
    // Motion
    stopObservingMotion()
  }
  
  override func shouldAutorotate() -> Bool {
    return true
  }
  
  override func prefersStatusBarHidden() -> Bool {
    return true
  }
  
  // MARK: - Scene
  func presentStartScene() -> StartScene {
    let scene = StartScene(size: SceneSize)
    scene.scaleMode = .AspectFill
    scene.startSceneDelegate = self
    
    // Present scene
    skView.presentScene(scene)
    skView.paused = false
    scene.appear()
    
    // Background music
    playMusicIfNeeded()
    
    return scene
  }
  
  func presentGameScene() -> GameScene {
    let scene = GameScene(size: SceneSize, gameData: gameData)
    scene.scaleMode = .AspectFill
    scene.gameSceneDelegate = self
    scene.motionDataSource = self
    
    // Present scene
    skView.presentScene(scene)
    skView.paused = false
    
    // Background music
    playMusicIfNeeded()
    
    return scene
  }
  
  func preloadAndPresentStartScene(completion: ((StartScene) -> Void)? = nil) {
    
    autoreleasepool { () -> () in
        let textureAtlases: [SKTextureAtlas] = [
            SKTextureAtlas(named: TextureAtlasFileName.UserInterface)
        ]
        
        let textures: [SKTexture] = [
            SKTexture(imageNamed: TextureFileName.Background),
            SKTexture(imageNamed: TextureFileName.BackgroundStars),
            SKTexture(imageNamed: TextureFileName.StartLogo)
        ]
        
        // Show loading scene
        presentLoadingScene(.Blank)
        
        // Preload textures
        preloadTextures(textures, textureAtlases: textureAtlases) { [weak self] in
            // Present game scene
            if let scene = self?.presentStartScene() {
                // Retain preloaded textures
                scene.textureAtlases = textureAtlases
                scene.textures = textures
                
                completion?(scene)
            }
        }
    }
    
    
  }
  
  func preloadAndPresentGameScene(completion: ((GameScene) -> Void)? = nil) {
    
    autoreleasepool { () -> () in
        let textureAtlases: [SKTextureAtlas] = [
            SKTextureAtlas(named: TextureAtlasFileName.Environment),
            SKTextureAtlas(named: TextureAtlasFileName.Character),
            SKTextureAtlas(named: TextureAtlasFileName.UserInterface)
        ]
        
        let textures: [SKTexture] = [
            SKTexture(imageNamed: TextureFileName.Background),
            SKTexture(imageNamed: TextureFileName.BackgroundSmallPlanets),
            SKTexture(imageNamed: TextureFileName.BackgroundSmallPlanets, index: 2),
            SKTexture(imageNamed: TextureFileName.BackgroundLargePlanets),
            SKTexture(imageNamed: TextureFileName.BackgroundLargePlanets, index: 2),
            SKTexture(imageNamed: TextureFileName.BackgroundStars),
            SKTexture(imageNamed: TextureFileName.PlanetGround)
        ]
        
        // Show loading scene
        presentLoadingScene()
        
        // Preload textures
        preloadTextures(textures, textureAtlases: textureAtlases) { [weak self] in
            // Present game scene
            if let scene = self?.presentGameScene() {
                // Retain preloaded textures
                scene.textureAtlases = textureAtlases
                scene.textures = textures
                
                completion?(scene)
            }
        }

    }
    
   
    }
  
  func presentLoadingScene(type: LoadingSceneType = .Regular) -> LoadingScene {
    let scene = LoadingScene(size: SceneSize, type: type)
    scene.scaleMode = .AspectFill
    
    // Present scene
    skView.presentScene(scene)
    skView.paused = false
    
    return scene
  }
  
  // MARK: - Motion
  func observeMotion() {
    // Motion manager
    if motionManager.accelerometerAvailable && !motionManager.accelerometerActive {
      motionManager.accelerometerUpdateInterval = 1/100
      motionManager.startAccelerometerUpdates()
    }
  }
  
  func stopObservingMotion() {
    motionManager.stopAccelerometerUpdates()
  }
  
  // MARK: - Leaderboard
  func presentLeaderboard() {
    if let leaderboardIdentifier = gameCenterManager.leaderboardIdentifier where gameCenterManager.isAuthenticated {
      presentLeaderboardViewControllerWithIdentifier(leaderboardIdentifier)
    } else {
      let message = "Please log into GameCenter to access the leaderboard"
      let alertController = UIAlertController(title: nil, message: message, preferredStyle: .Alert)
      let cancelAlertAction = UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Default, handler: nil)
      let okAlertAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.Default) { _ in
        self.gameCenterManager.promptLocalPlayerAuthentication()
      }
      
      alertController.addAction(okAlertAction)
      alertController.addAction(cancelAlertAction)
      
      presentViewController(alertController, animated: true, completion: nil)
    }
  }

  func presentLeaderboardViewControllerWithIdentifier(identifier: String) -> GKGameCenterViewController {
    let leaderboardViewController = GKGameCenterViewController()
    
    leaderboardViewController.gameCenterDelegate = self
    leaderboardViewController.viewState = .Leaderboards
    leaderboardViewController.leaderboardIdentifier = identifier
    
    skView.paused = true

    presentViewController(leaderboardViewController, animated: true, completion: nil)
    
    return leaderboardViewController
  }
  
  // MARK: - Ad
  func prepareInterstitialAd() {
    interstitialAd = ADInterstitialAd()
    interstitialAd!.delegate = self
  }

  func presentInterstitialAd() -> Bool {
    if isAdsEnabled() == false {
      print("Ads are disabled")
      
      return false
    } else if interstitialAd?.loaded != true {
      print("Ad not loaded")
      
      return false
    }

    // Container view
<<<<<<< HEAD
    /*interstitialAdView = InterstitialAdView(frame: skView.bounds) //NOW
    interstitialAdView!.closeButton.addTarget(self, action: #selector(GameViewController.closeInterstitialAd), forControlEvents: .TouchUpInside)
    skView.addSubview(interstitialAdView!)*/
=======
    interstitialAdView = InterstitialAdView(frame: skView.bounds)
    interstitialAdView!.closeButton.addTarget(self, action: "closeInterstitialAd", forControlEvents: .TouchUpInside)
    skView.addSubview(interstitialAdView!)
>>>>>>> a645440bc6253e07b2ce0e4c5668f4683c179008
    
    // Pause view
    skView.paused = true
    
    // Present ad in view
    //interstitialAdView!.presentInterstitialAd(interstitialAd!) ///NOW
    
    return true
  }
  
  func closeInterstitialAd() {
    // Clean up
    //interstitialAdView?.removeFromSuperview() //NOW
    resetInterstitialAd()
    
    // Restart game
    dispatch_async(dispatch_get_main_queue()) {
      if let gameScene = self.skView.scene as? GameScene {
        // Unpause view
        self.skView.paused = false

        gameScene.startGame()
      }
    }
  }
  
  func resetInterstitialAd() {
    interstitialAd?.delegate = nil
    interstitialAd = nil
    //interstitialAdView = nil //NOW
  }
  
  // MARK: - IAP
  func presentStoreActionSheet() {
    if let removeAdsProduct = removeAdsProduct {
      let actionController = UIAlertController(title: nil, message: nil, preferredStyle: .ActionSheet)
      let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel, handler: nil)

      let purchaseAction = UIAlertAction(title: "Remove ads for \(removeAdsProduct.formattedPrice)", style: .Default) { _ in
        LoadingIndicatorView.sharedView.showInView(self.view)

        self.purchaseProduct(removeAdsProduct)
      }

      let restoreAction = UIAlertAction(title: "Restore purchase", style: .Default) { _ in
        LoadingIndicatorView.sharedView.showInView(self.view)

        self.restoreProducts()
      }
      
      actionController.addAction(purchaseAction)
      actionController.addAction(restoreAction)
      actionController.addAction(cancelAction)
    
      presentViewController(actionController, animated: true, completion: nil)
    }
  }
  
  func requestProducts() {
    let productIdentifiers = Set([ProductIdentifier.RemoveAds])
    let request = SKProductsRequest(productIdentifiers: productIdentifiers)
    
    request.delegate = self
    request.start()
  }
  
  func purchaseProduct(product: SKProduct) {
    let payment = SKPayment(product: product)
    let paymentQueue = SKPaymentQueue.defaultQueue()
    
    paymentQueue.addPayment(payment)
  }
  
  func restoreProducts() {
    let paymentQueue = SKPaymentQueue.defaultQueue()
    
    paymentQueue.restoreCompletedTransactions()
  }
  
  // MARK: - Sound
  func playMusicIfNeeded() {
    if isMusicEnabled() {
      if SKTAudio.sharedInstance().backgroundMusicPlayer?.playing != true {
        SKTAudio.sharedInstance().playBackgroundMusic(SoundFileName.BackgroundMusic, volume: 0.3)
      }
    } else {
      SKTAudio.sharedInstance().pauseBackgroundMusic()
    }
  }

  func playMusic() {
    SKTAudio.sharedInstance().playBackgroundMusic(SoundFileName.BackgroundMusic)
  }
  
  func stopMusic() {
    SKTAudio.sharedInstance().pauseBackgroundMusic()
  }

  func toggleSoundForScene(scene: SKScene, withButton button: SpriteButtonNode) -> Bool {
    let userDefaults = NSUserDefaults.standardUserDefaults()
    
    if isSoundEnabled() {
      userDefaults.setValue(true, forKey: KeyForUserDefaults.SoundDisabled)
      button.state = .Active
    } else {
      userDefaults.setValue(false, forKey: KeyForUserDefaults.SoundDisabled)
      button.state = .Normal
    }
    
    userDefaults.synchronize()
    
    return isSoundEnabled()
  }
  
  func toggleMusicForScene(scene: SKScene, withButton button: SpriteButtonNode) -> Bool {
    let userDefaults = NSUserDefaults.standardUserDefaults()
    
    if isMusicEnabled() {
      userDefaults.setValue(true, forKey: KeyForUserDefaults.MusicDisabled)
      button.state = .Active
      stopMusic()
    } else {
      userDefaults.setValue(false, forKey: KeyForUserDefaults.MusicDisabled)
      button.state = .Normal
      playMusic()
    }
    
    userDefaults.synchronize()
    
    return isMusicEnabled()
  }
  
  // MARK: - Notification
  func applicationWillResignActive(notification: NSNotification) {
    SKTAudio.sharedInstance().pauseBackgroundMusic()
  }
  
  func applicationDidBecomeActive(notification: NSNotification) {
    SKTAudio.sharedInstance().resumeBackgroundMusic()
  }

  func paymentTransactionDidComplete(notification: NSNotification) {
    restoreViewFromTransaction()
  }
  
  func paymentTransactionDidRestore(notification: NSNotification) {
    restoreViewFromTransaction()
  }
  
  func paymentTransactionDidFail(notification: NSNotification) {
    restoreViewFromTransaction()
  }
  
  private func restoreViewFromTransaction() {
    LoadingIndicatorView.sharedView.dismiss()
    
    skView.paused = false
  }
  
  // MARK: - GKGameCenterControllerDelegate
  func gameCenterViewControllerDidFinish(gameCenterViewController: GKGameCenterViewController) {
    gameCenterViewController.dismissViewControllerAnimated(true, completion: nil)

    skView.paused = false
  }
  
  // MARK: - GameCenterManagerDelegate
  func gameCenterManager(manager: GameCenterManager, didProvideViewController viewController: UIViewController) {
    presentViewController(viewController, animated: true, completion: nil)
  }
  
  func gameCenterManager(manager: GameCenterManager, didAuthenticateLocalPlayer: Bool) {
    if didAuthenticateLocalPlayer {
      gameCenterManager.loadDefaultLeaderboardIdentifier()
    }
  }
  
  func gameCenterManager(manager: GameCenterManager, didReceiveError error: NSError) {
    // Cancelled by user
    LoadingIndicatorView.sharedView.dismiss()
  }
  
  func gameCenterManager(manager: GameCenterManager, didLoadDefaultLeaderboardIdentifier identifier: String) {
    gameCenterManager.loadLeaderboardScore()
  }
  
  func gameCenterManager(manager: GameCenterManager, didLoadLocalPlayerScore score: GKScore) {
    gameData.updateTopScoreWithGKScore(score)
    
    LoadingIndicatorView.sharedView.dismiss()
  }
  
  // MARK: - GameSceneDelegate
  func gameSceneDidEnd(gameScene: GameScene) {
    if !gameScene.godMode && gameCenterManager.isAuthenticated {
      let scoreValue = Int64(round(gameScene.gameData.score))

      gameCenterManager.reportScoreValue(scoreValue)
    }
  }
  
  func gameSceneDidStart(gameScene: GameScene) {
    //prepareInterstitialAd() //JUST DELETED
  }
  
  func gameSceneDidRequestRetry(gameScene: GameScene) {
    // Show ad or restart game
    if numberOfRetriesSinceLastAd < MinimumNumberOfRetriesBeforePresentingAd || !presentInterstitialAd() {
      numberOfRetriesSinceLastAd = 0
      
      gameScene.startGame()
    } else {
      numberOfRetriesSinceLastAd = 0
    }
  }
  
  func gameSceneDidRequestQuit(gameScene: GameScene) {
    presentStartScene()
  }
  
  func gameSceneDidRequestLeaderboard(gameScene: GameScene) {
    presentLeaderboard()
  }
  
  func gameSceneDidRequestToggleSound(gameScene: GameScene, withButton button: SpriteButtonNode) {
    toggleSoundForScene(gameScene, withButton: button)
  }

  func gameSceneDidRequestToggleMusic(gameScene: GameScene, withButton button: SpriteButtonNode) {
    toggleMusicForScene(gameScene, withButton: button)
  }
    
    
    func gameSceneDidRequestToShowEnemiesView(gameScene: GameScene, withHighestUserScore: Int) {
        gameScene.view?.paused = false
        gameScene.pauseMenu?.removeFromParent()
        gameScene.enemiesView = gameScene.presentEnemiesGameView(withHighestUserScore)
        afterDelay(0.05) { [weak gameScene] in
            gameScene!.view?.paused = true
        }
    }
  
    func gameSceneDidRequestToDismissEnemiesView(gameScene: GameScene) {
        gameScene.view?.paused = false
        gameScene.enemiesView?.removeFromParent()
        gameScene.pauseMenu = gameScene.presentPauseMenu()
        afterDelay(0.05) { [weak gameScene] in
            gameScene!.view?.paused = true
        }

    }
    
  // MARK: - MotionDataSource
  func accelerometerDataForScene(scene: SKScene) -> CMAccelerometerData? {
    return motionManager.accelerometerData
  }
  
  // MARK: - StartSceneDelegate
  func startSceneDidRequestStart(startScene: StartScene) {
    preloadAndPresentGameScene()
  }

  func startSceneDidRequestLeaderboard(startScene: StartScene) {
    presentLeaderboard()
  }
  
  func startSceneDidRequestStore(stareScene: StartScene) {
    LoadingIndicatorView.sharedView.showInView(view)

    requestProducts()
  }
  
  func startSceneDidRequestToggleSound(startScene: StartScene, withButton button: SpriteButtonNode) {
    toggleSoundForScene(startScene, withButton: button)
  }

  func startSceneDidRequestToggleMusic(startScene: StartScene, withButton button: SpriteButtonNode) {
    toggleMusicForScene(startScene, withButton: button)
  }
  
  // MARK: - ADInterstitialAdDelegate
  func interstitialAdDidUnload(interstitialAd: ADInterstitialAd!) {
    resetInterstitialAd()
  }
  
  func interstitialAd(interstitialAd: ADInterstitialAd!, didFailWithError error: NSError!) {
    resetInterstitialAd()
    
    print(error)
  }

  func interstitialAdDidLoad(interstitialAd: ADInterstitialAd!) {
    print("Ad loaded")
  }
  
  func interstitialAdActionDidFinish(interstitialAd: ADInterstitialAd!) {
    if interstitialAd?.loaded == true {
      closeInterstitialAd()
    }
  }
  
  // MARK: - SKProductsRequestDelegate
  func productsRequest(request: SKProductsRequest, didReceiveResponse response: SKProductsResponse) {
    products = response.products
    
    if let products = products {
      for product in products {
        if product.productIdentifier == ProductIdentifier.RemoveAds {
          removeAdsProduct = product
        }
        
        break
      }
    }

    // Hide indicator
    LoadingIndicatorView.sharedView.dismiss()

    // Present products
    presentStoreActionSheet()
  }
    
  override func viewWillLayoutSubviews() {

        super.viewWillLayoutSubviews();
        
        
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
        appDelegate.viewController = self;
    }
}

