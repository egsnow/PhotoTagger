

import UIKit
import SwiftyJSON
import Alamofire


class ViewController: UIViewController {

  
  // MARK: - IBOutlets
  @IBOutlet var takePictureButton: UIButton!
  @IBOutlet var imageView: UIImageView!
  @IBOutlet var progressView: UIProgressView!
  @IBOutlet var activityIndicatorView: UIActivityIndicatorView!

  
  // MARK: - Properties
  private var tags: [String]?
  private var colors: [PhotoColor]?

  
  // MARK: - View Life Cycle
  override func viewDidLoad() {
    super.viewDidLoad()
    if !UIImagePickerController.isSourceTypeAvailable(.camera) {
      takePictureButton.setTitle("Select Photo", for: .normal)
    }
  }

  
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    imageView.image = nil
  }

  
  // MARK: - Navigation
  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    if segue.identifier == "ShowResults",
      let controller = segue.destination as? TagsColorsViewController {
      controller.tags = tags
      controller.colors = colors
    }
  }

  
  // MARK: - IBActions
  @IBAction func takePicture(_ sender: UIButton) {
    let picker = UIImagePickerController()
    picker.delegate = self
    picker.allowsEditing = false
    if UIImagePickerController.isSourceTypeAvailable(.camera) {
      picker.sourceType = .camera
    } else {
      picker.sourceType = .photoLibrary
      picker.modalPresentationStyle = .fullScreen
    }
    present(picker, animated: true)
  }
}


// MARK: - UIImagePickerControllerDelegate
extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  
  
  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String: Any]) {
    guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else {
      print("Info did not have the required UIImage for the Original Image")
      dismiss(animated: true)
      return
    }
    imageView.image = image
    takePictureButton.isHidden = true
    progressView.progress = 0.0
    progressView.isHidden = false
    activityIndicatorView.startAnimating()
    upload(image: image, progressCompletion: { [weak self] percent in
            self?.progressView.setProgress(percent, animated: true)
      },
           completion: { [weak self] tags, colors in
            self?.takePictureButton.isHidden = false
            self?.progressView.isHidden = true
            self?.activityIndicatorView.stopAnimating()
            self?.tags = tags
            self?.colors = colors
            self?.performSegue(withIdentifier: "ShowResults", sender: self)
    })
    dismiss(animated: true)
  }
}


extension ViewController {
  
  
  func upload(image: UIImage, progressCompletion: @escaping (_ percent: Float) -> Void, completion: @escaping (_ tags: [String]?, _ colors: [PhotoColor]?) -> Void) {
    guard let imageData = UIImageJPEGRepresentation(image, 0.5) else {
      print("Could not get JPEG representation of UIImage")
      return
    }
    Alamofire.upload(multipartFormData: { multipartFormData in
      multipartFormData.append(imageData,
                               withName: "imagefile",
                               fileName: "image.jpg",
                               mimeType: "image/jpeg")
    },
                     with: ImaggaRouter.content,
                     encodingCompletion: { encodingResult in
                      switch encodingResult {
                      case .success(let upload, _, _):
                        upload.uploadProgress { progress in
                          progressCompletion(Float(progress.fractionCompleted))
                        }
                        upload.validate()
                        upload.responseJSON { response in
                          guard response.result.isSuccess,
                            let value = response.result.value else {
                              print("Error while uploading file: \(String(describing: response.result.error))")
                              completion(nil, nil)
                              return
                          }
                          
                          let firstFileID = JSON(value)["uploaded"][0]["id"].stringValue
                          print("Content uploaded with ID: \(firstFileID)")
                          
                          self.downloadTags(contentID: firstFileID) { tags in
                            self.downloadColors(contentID: firstFileID) { colors in
                              completion(tags, colors)
                            }
                          }
                        }
                      case .failure(let encodingError):
                        print(encodingError)
                      }
    })
  }

  
  func downloadTags(contentID: String, completion: @escaping ([String]?) -> Void) {
    Alamofire.request(ImaggaRouter.tags(contentID))
      .responseJSON { response in
        guard response.result.isSuccess,
          let value = response.result.value else {
            print("Error while fetching tags: \(String(describing: response.result.error))")
            completion(nil)
            return
        }
        let tags = JSON(value)["results"][0]["tags"].array?.map { json in
          json["tag"].stringValue
        }
        completion(tags)
    }
  }


  func downloadColors(contentID: String, completion: @escaping ([PhotoColor]?) -> Void) {
    Alamofire.request(ImaggaRouter.colors(contentID))
      .responseJSON { response in
        guard response.result.isSuccess,
          let value = response.result.value else {
            print("Error while fetching colors: \(String(describing: response.result.error))")
            completion(nil)
            return
        }
        let photoColors = JSON(value)["results"][0]["info"]["image_colors"].array?.map { json in
          PhotoColor(red: json["r"].intValue,
                     green: json["g"].intValue,
                     blue: json["b"].intValue,
                     colorName: json["closest_palette_color"].stringValue)
        }
        completion(photoColors)
    }
  }
}
