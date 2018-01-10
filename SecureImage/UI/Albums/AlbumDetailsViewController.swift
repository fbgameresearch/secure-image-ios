//
// SecureImage
//
// Copyright © 2017 Province of British Columbia
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Created by Jason Leach on 2017-12-14.
//

import UIKit
import RealmSwift

class AlbumDetailsViewController: UIViewController {
    
    @IBOutlet weak var tableView: UITableView!
    
    private static let captureImageSegueID = "CaptureImageSegue"
    private static let showImageSegueID = "ShowImageSegue"
    private static let showAllImagesSegueID = "ShowAllImagesSegue"
    private static let previewCellReuseID = "ImagePreviewCellID"
    private static let functionsCellReuseID = "FunctionsCellID"
    private static let annotationCellReuseID = "AnnotationCellID"
    private static let functionsCellRowHeight: CGFloat = 60.0
    private static let annotationCellRowHeight: CGFloat = 100.0
    private static let annotationCellsOffset: Int = 2
    private static let numberOfRows: Int = annotationCellsOffset + Constants.Album.Fields.count
    private var document: Document?
    private var previewCellHeight: CGFloat = 250.0
    private let locationServices: LocationServices = {
        let ls = LocationServices()
        ls.start()
        
        return ls
    }()
    internal var album: Album! // TODO:(jl) Should this be force unwraped?
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        guard let _ = album else {
            fatalError("The album was not passed to \(AlbumDetailsViewController.self())")
        }
        
        commonInit()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        super.viewWillAppear(animated)
        
        tableView.reloadData()
    }

    override func willRotate(to toInterfaceOrientation: UIInterfaceOrientation, duration: TimeInterval) {
        
        tableView.reloadData()
    }
    
    // MARK: - Navigation
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if let document = document, let dvc = segue.destination as? PhotoViewController,
            segue.identifier == AlbumDetailsViewController.showImageSegueID {
            
            dvc.document = document
            return
        }
        
        if let dvc = segue.destination as? PhotosViewController,
            segue.identifier == AlbumDetailsViewController.showAllImagesSegueID {
            
            dvc.album = album
            return
        }
        
        if let dvc = segue.destination as? SecureCameraViewController, segue.identifier == AlbumDetailsViewController.captureImageSegueID {
            dvc.delegate = self
            
            return
        }
    }
    
    // MARK: -
    
    private func commonInit() {
        
        NotificationCenter.default.addObserver(self, selector: #selector(AlbumDetailsViewController.keyboardWillShow),
                                               name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(AlbumDetailsViewController.keyboardWillHide),
                                               name: NSNotification.Name.UIKeyboardWillHide, object: nil)
        
        tableView.dataSource = self
        tableView.delegate = self
    }
    
    private func configureCell(cell: UITableViewCell, at indexPath: IndexPath) {
        
        guard let identifier = cell.reuseIdentifier else {
            fatalError("Unable to determine cell reuse ID")
        }
        
        self.tableView.isEditing = false
        
        switch identifier {
        case AlbumDetailsViewController.previewCellReuseID:
            let cell = cell as! ImagePreviewTableViewCell
            cell.previewImages = album.documents
            cell.onViewImageTouched = { (document: Document) in
                self.document = document
                self.performSegue(withIdentifier: AlbumDetailsViewController.showImageSegueID, sender: nil)
            }
            cell.onAddImageTouched = {
                self.performSegue(withIdentifier: AlbumDetailsViewController.captureImageSegueID, sender: nil)
            }
            previewCellHeight = cell.collectionViewRowHeightFor(tableView.frame.width) * 2.0 + ImagePreviewTableViewCell.insets.bottom
        case AlbumDetailsViewController.functionsCellReuseID:
            let cell = cell as! FuncitonTableViewCell
            
            cell.onViewAllImagesTouched = {
                self.performSegue(withIdentifier: AlbumDetailsViewController.showAllImagesSegueID, sender: nil)
            }
            cell.onUploadAlbumTouched = {
                print("I should upload")
            }
        default:
            let cell = cell as! AlbumPropertyTableViewCell
            let property = Constants.Album.Fields[indexPath.row - AlbumDetailsViewController.annotationCellsOffset]
            
            cell.attributeTitleLabel.text = property.name
            if let key = property.name.toCammelCase(), let value = album.value(forKey: key) as? String, !value.isEmpty {
                cell.attributeTextField.text = value
            } else {
                cell.attributeTextField.placeholder = property.placeHolderText
            }
            
            cell.onPropertyChanged = { (property: String, value: String) in
                self.updateAlbum(property: property, value: value)
            }
        }
    }
    
    private func cellIdentifierForCell(at indexPath: IndexPath) -> String {
        
        var identifier = ""
        
        switch indexPath.row {
        case 0:
            identifier = AlbumDetailsViewController.previewCellReuseID
        case 1:
            identifier = AlbumDetailsViewController.functionsCellReuseID
        default:
            identifier = AlbumDetailsViewController.annotationCellReuseID
        }
        
        return identifier
    }
    
    internal func updateAlbum(property: String, value: String) {
        
        do {
            let realm = try Realm()
            if let myAlbum = realm.objects(Album.self).filter("id == %@", album.id).first {
                try realm.write {
                    myAlbum.setValue(value, forKey: property)
                }
            }
        } catch {
            fatalError("Unable to update album properties")
        }
    }
    
    @objc dynamic private func keyboardWillShow(notification: NSNotification) {
        
        guard let keyboardFrame: NSValue = notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as? NSValue else {
            print("Could not extract the keyboard frame from the notification")
            return
        }
        
        // Get the cell the user is interacting with
        let keyboardRectangle = keyboardFrame.cgRectValue
        let keyboardHeight = keyboardRectangle.height
        let cell = tableView.visibleCells.map { (cell: UITableViewCell) -> UITableViewCell? in
            if let cell = cell as? AlbumPropertyTableViewCell, cell.attributeTextField.isFirstResponder {
                return cell
            }
            
            return nil
            }.filter { $0 != nil }.first
        
        // adjust the table so that the users current cell is just above
        // the top of the keyboard
        if let aCell = cell {
            // We want to move the table up the difference between the cells
            // current postion and the top of the keyboard.
            let delta = aCell!.center.y - keyboardHeight
            tableView.setContentOffset(CGPoint(x: 0, y: delta), animated: true)
        }
    }
    
    @objc dynamic private func keyboardWillHide(notification: NSNotification) {
        
        // reset the table to its initial state when the keyboard is gone
        tableView.setContentOffset(CGPoint(x: 0, y: 0), animated: true)
    }
}

// MARK: UITableViewDataSource
extension AlbumDetailsViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return AlbumDetailsViewController.numberOfRows
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let identifier = cellIdentifierForCell(at: indexPath)
        
        guard let cell = tableView.dequeueReusableCell(withIdentifier: identifier) else {
            fatalError("Unable to dequeue cell with identifier \(identifier)")
        }
        
        configureCell(cell: cell, at: indexPath)
        
        return cell
    }
}

// MARK: UITableViewDelegate
extension AlbumDetailsViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        let identifier = cellIdentifierForCell(at: indexPath)
        switch identifier
        {
        case AlbumDetailsViewController.previewCellReuseID:
            return previewCellHeight
        case AlbumDetailsViewController.functionsCellReuseID:
            return AlbumDetailsViewController.functionsCellRowHeight
        default:
            return AlbumDetailsViewController.annotationCellRowHeight
        }
    }
}

// MARK: SecureCameraImageCaptureDelegate
extension AlbumDetailsViewController: SecureCameraImageCaptureDelegate {
    
    func captured(image: Data) {
        
        guard let album = album else {
            fatalError("Unable unwrap album")
        }
        
        if let doc = DataServices.add(image: image, to: album) {
            locationServices.addLocation(to: doc)
        }
    }
}
