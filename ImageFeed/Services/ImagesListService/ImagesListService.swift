import Foundation
// 0=0
struct Photo: Codable {
    let id: String
    let size: CGSize
    let createdAt: Date?
    let description: String?
    let thumbImageURL: String
    let largeImageURL: String
    let regularImageURL: String
    let smallImageURL: String
    let isLiked: Bool
    
    init(_ photoData: PhotoResult, dateFormatter: DateFormatter) {
        self.id = photoData.id
        self.size = CGSize(width: photoData.width, height: photoData.height)
        self.createdAt = dateFormatter.date(from: photoData.createdAt ?? "")
        self.description = photoData.description
        self.thumbImageURL = photoData.urls.thumb
        self.largeImageURL = photoData.urls.full
        self.regularImageURL = photoData.urls.regular
        self.smallImageURL = photoData.urls.small
        self.isLiked = photoData.likedByUser
    }
}

struct PhotoResult: Decodable {
    let id: String
    let width: Int
    let height: Int
    let createdAt: String?
    let description: String?
    let urls: UrlsResult
    let likedByUser: Bool
}

struct UrlsResult: Decodable {
    let full: String
    let regular: String
    let small: String
    let thumb: String
}

struct PhotoLike: Decodable {
    let photo: PhotoResult
}

final class ImagesListService {
    
    static let shared = ImagesListService()
    
    static let didChangeNotification = Notification.Name(rawValue: "ImagesListServiceDidChange")
    
    private let urlSession = URLSession.shared
    
    private let dateFormatter = DateFormatter()
    
    private(set) var photos: [Photo] = []
    
    private var lastLoadedPage: Int?
    private var currentTask: URLSessionTask?
    
    // MARK: - Public Methods
    
    func fetchPhotosNextPage() {
        assert(Thread.isMainThread)
        
        guard currentTask == nil else {
            return
        }
        
        let nextPage = (lastLoadedPage ?? 0) + 1
        
        guard let request = makeRequest(page: nextPage) else {
            print("Ошибка при создании запроса")
            return
        }
        
        let task = urlSession.objectTask(for: request) { [weak self] (result: Result<[PhotoResult], Error>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let photoResults):
                    if self.lastLoadedPage == nil {
                        self.lastLoadedPage = 1
                    } else {
                        self.lastLoadedPage! += 1
                    }
                    
                    let newPhotos = photoResults.map { Photo($0, dateFormatter: self.dateFormatter) }
                    self.photos.append(contentsOf: newPhotos)
                    
                    NotificationCenter.default.post(name: ImagesListService.didChangeNotification,
                                                    object: nil)
                    
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
            
            self.currentTask = nil
        }
        
        self.currentTask = task
        task.resume()
    }
    
    func changeLike(photoId: String, isLike: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        if let currentTask = currentTask {
            currentTask.cancel()
        }
        
        guard let request = makeLikeRequest(photoId: photoId, isLike: isLike) else {
            print("Ошибка при создании запроса")
            return
        }
        
        let task = urlSession.objectTask(for: request) { (result: Result<PhotoLike, Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    if let index = self.photos.firstIndex(where: { $0.id == photoId }) {
                        let photo = self.photos[index]
                        let newPhotoResult = PhotoResult(id: photo.id,
                                                         width: Int(photo.size.width),
                                                         height: Int(photo.size.height),
                                                         createdAt: photo.createdAt?.description,
                                                         description: photo.description,
                                                         urls: UrlsResult(full: photo.largeImageURL,
                                                                          regular: photo.regularImageURL,
                                                                          small: photo.smallImageURL,
                                                                          thumb: photo.thumbImageURL),
                                                         likedByUser: !photo.isLiked)
                        let newPhoto = Photo(newPhotoResult, dateFormatter: self.dateFormatter)
                        self.photos[index] = newPhoto
                        completion(.success(()))
                    }
                    
                case .failure(let error):
                    print("Ошибка при изменении лайка: \(error)")
                    completion(.failure(error))
                }
            }
        }
        
        self.currentTask = task
        task.resume()
    }
    
    // MARK: - Private Methods
    
    private func makeRequest(page: Int) -> URLRequest? {
        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "10")
        ]
        
        let baseURLString = defaultBaseURL.absoluteString
        return URLRequest.makeHTTPRequest(path: "/photos",
                                          httpMethod: "GET",
                                          queryItems: queryItems,
                                          baseURL: baseURLString)
    }

    private func makeLikeRequest(photoId: String, isLike: Bool) -> URLRequest? {
        let baseURLString = defaultBaseURL.absoluteString
        return URLRequest.makeHTTPRequest(path: "/photos/\(photoId)/like",
                                          httpMethod: isLike ? "POST" : "DELETE",
                                          baseURL: baseURLString)
    }
}

