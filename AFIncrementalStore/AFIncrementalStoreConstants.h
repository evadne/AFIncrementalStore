//  AFIncrementalStoreConstants.h

#import <Foundation/Foundation.h>

///----------------
/// @name Constants
///----------------

/**
 The name of the exception called when `AFIncrementalStore` or a subclass is attempted to be used, without implementing one of the required methods.
 */
extern NSString * const AFIncrementalStoreUnimplementedMethodException;

/**
	The name of the exception called when `AFIncrementalStore` attempts to import remote representations for a relationship and encounter a to-one or to-many cardinality mismatch.
*/
extern NSString * const AFIncrementalStoreRelationshipCardinalityException;

///--------------------
/// @name Attributes
///--------------------

/**
	The name of the remote resource identifier stored in the backing persistent store.
*/
extern NSString * const AFIncrementalStoreResourceIdentifierAttributeName;

///--------------------
/// @name Error Domains
///--------------------

/**
	The name for all errors incurred within the incremental store.
*/
extern NSString * const AFIncrementalStoreErrorDomain;

///--------------------
/// @name Notifications
///--------------------

/**
 Posted before an HTTP request operation starts. 
 The object is the managed object context of the request.
 The notification `userInfo` contains the finished request operation, keyed at `AFIncrementalStoreRequestOperationKey`, as well as the associated persistent store request, if applicable, keyed at `AFIncrementalStorePersistentStoreRequestKey`.
 */
extern NSString * const AFIncrementalStoreContextWillFetchRemoteValues;

/**
 Posted after an HTTP request operation finishes. 
 The object is the managed object context of the request. 
 The notification `userInfo` contains the finished request operation, keyed at `AFIncrementalStoreRequestOperationKey`, as well as the associated persistent store request, if applicable, keyed at `AFIncrementalStorePersistentStoreRequestKey`.
 */
extern NSString * const AFIncrementalStoreContextDidFetchRemoteValues;

/**
 A key in the `userInfo` dictionary in a `AFIncrementalStoreContextWillFetchRemoteValues` or `AFIncrementalStoreContextDidFetchRemoteValues` notification.
 The corresponding value is an `AFHTTPRequestOperation` object representing the associated request. */
extern NSString * const AFIncrementalStoreRequestOperationKey;

/**
 A key in the `userInfo` dictionary in a `AFIncrementalStoreContextWillFetchRemoteValues` or `AFIncrementalStoreContextDidFetchRemoteValues` notification.
 The corresponding value is an `NSPersistentStoreRequest` object representing the associated fetch or save request. */
extern NSString * const AFIncrementalStorePersistentStoreRequestKey;

///--------------------
/// @name Functions
///--------------------

extern NSError * AFIncrementalStoreError (NSUInteger code, NSString *localizedDescription);
