//  AFIncrementalStoreConstants.m

#import "AFIncrementalStoreConstants.h"

NSString * const AFIncrementalStoreUnimplementedMethodException = @"com.alamofire.incremental-store.exceptions.unimplemented-method";
NSString * const AFIncrementalStoreRelationshipCardinalityException = @"com.alamofire.incremental-store.exceptions.relationship-cardinality";

NSString * const AFIncrementalStoreResourceIdentifierAttributeName = @"__af_resourceIdentifier";
NSString * const AFIncrementalStoreErrorDomain = @"AFIncrementalStoreErrorDomain";

NSString * const AFIncrementalStoreContextWillFetchRemoteValues = @"AFIncrementalStoreContextWillFetchRemoteValues";
NSString * const AFIncrementalStoreContextDidFetchRemoteValues = @"AFIncrementalStoreContextDidFetchRemoteValues";
NSString * const AFIncrementalStoreRequestOperationKey = @"AFIncrementalStoreRequestOperation";
NSString * const AFIncrementalStorePersistentStoreRequestKey = @"AFIncrementalStorePersistentStoreRequest";

NSError * AFIncrementalStoreError (NSUInteger code, NSString *localizedDescription) {

	return [NSError errorWithDomain:AFIncrementalStoreErrorDomain code:code userInfo:@{
		NSLocalizedDescriptionKey: localizedDescription
	}];

};
