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

import Foundation
import RealmSwift

class Document: Object {
    
    @objc dynamic var id: String = UUID().uuidString
    @objc dynamic var remoteDocumentId: String?
    @objc dynamic var createdAt: Date = Date()
    @objc dynamic var modifiedAt: Date = Date()
    @objc dynamic var imageData: Data?
    @objc dynamic var latitude: Double = 0.0
    @objc dynamic var longitude: Double = 0.0

    override class func primaryKey() -> String {
        return "id"
    }
}
