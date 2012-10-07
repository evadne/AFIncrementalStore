// AFIncrementalStore.h
//
// Copyright (c) 2012 Mattt Thompson (http://mattt.me)
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <CoreData/CoreData.h>
#import "AFNetworking.h"
#import "AFIncrementalStoreHTTPClient.h"
#import "AFIncrementalStoreConstants.h"

@protocol AFIncrementalStoreDelegate;
@protocol AFIncrementalStoreHTTPClient;

/**
 `AFIncrementalStore` is an abstract subclass of `NSIncrementalStore`, designed to allow you to load and save data incrementally to and from a one or more web services.
 
 ## Subclassing Notes
 
 ### Methods to override
 
 In a subclass of `AFIncrementalStore`, you _must_ override the following methods to provide behavior appropriate for your store:
    
    - +type
    - +model
 
 Additionally, all `NSPersistentStore` subclasses, and thus all `AFIncrementalStore` subclasses must do `NSPersistentStoreCoordinator +registerStoreClass:forStoreType:` in order to be created by `NSPersistentStoreCoordinator -addPersistentStoreWithType:configuration:URL:options:error:`. It is recommended that subclasses register themselves in their own `+initialize` method.
 */
@interface AFIncrementalStore : NSIncrementalStore {
	@package
		NSPersistentStoreCoordinator *_backingPersistentStoreCoordinator;
		NSManagedObjectContext *_backingManagedObjectContext;
		NSMutableDictionary *_registeredObjectIDsByResourceIdentifier;
		NSOperationQueue *_operationQueue;
}

///---------------------------------------------
/// @name Accessing Incremental Store Properties
///---------------------------------------------

/**
 The HTTP client used to manage requests and responses with the associated web services.
 */
@property (nonatomic, strong) AFHTTPClient <AFIncrementalStoreHTTPClient> *HTTPClient;

/**
 The persistent store coordinator used to persist data from the associated web serivices locally.
 
 @discussion Rather than persist values directly, `AFIncrementalStore` manages and proxies through a persistent store coordinator.
 */
@property (readonly) NSPersistentStoreCoordinator *backingPersistentStoreCoordinator;

///-----------------------
/// @name Required Methods
///-----------------------

/**
 Returns the string used as the `NSStoreTypeKey` value by the application's persistent store coordinator.
 
 @return The string used to describe the type of the store.
 */
+ (NSString *)type;

/**
 Returns the managed object model used by the store.
 
 @return The managed object model used by the store
 */
+ (NSManagedObjectModel *)model;

@end
