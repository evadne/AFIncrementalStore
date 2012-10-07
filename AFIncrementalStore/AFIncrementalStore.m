// AFIncrementalStore.m
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

#import "AFIncrementalStore.h"
#import "AFIncrementalStore+BackingStore.h"
#import "AFIncrementalStore+Faulting.h"
#import "AFIncrementalStore+Fetching.h"
#import "AFIncrementalStore+Importing.h"
#import "AFIncrementalStore+Notifications.h"
#import "AFIncrementalStore+ObjectIDs.h"
#import "AFIncrementalStore+Relationships.h"
#import "AFIncrementalStore+Saving.h"
#import "AFIncrementalStoreReferenceObject.h"

@implementation AFIncrementalStore {
	NSCache *_propertyValuesCache;
	NSCache *_relationshipsCache;
	NSCache *_backingObjectIDByObjectID;
}
@synthesize HTTPClient = _HTTPClient;
@dynamic backingPersistentStoreCoordinator;

+ (NSString *) type {
	
	@throw [NSException exceptionWithName:AFIncrementalStoreUnimplementedMethodException reason:NSLocalizedString(@"Unimplemented method: +type. Must be overridden in a subclass", nil) userInfo:nil];
	
}

+ (NSManagedObjectModel *) model {

	@throw [NSException exceptionWithName:AFIncrementalStoreUnimplementedMethodException reason:NSLocalizedString(@"Unimplemented method: +model. Must be overridden in a subclass", nil) userInfo:nil];
	
}

- (BOOL) loadMetadata:(NSError *__autoreleasing *)error {
  
	if (!_propertyValuesCache) {

		self.metadata = @{
			NSStoreUUIDKey: [[NSProcessInfo processInfo] globallyUniqueString],
			NSStoreTypeKey: NSStringFromClass([self class])
		};

		_propertyValuesCache = [[NSCache alloc] init];
		_relationshipsCache = [[NSCache alloc] init];
		_backingObjectIDByObjectID = [[NSCache alloc] init];
		_registeredObjectIDsByResourceIdentifier = [NSMutableDictionary dictionary];

		return YES;
		
	}
	
	return NO;
	
}

- (id) executeRequest:(NSPersistentStoreRequest *)persistentStoreRequest withContext:(NSManagedObjectContext *)context error:(NSError **)error {

	NSPersistentStoreRequestType const requestType = [persistentStoreRequest requestType];
	
	if (requestType == NSFetchRequestType)
	if ([persistentStoreRequest isKindOfClass:[NSFetchRequest class]]) {
		return [self executePersistentStoreFetchRequest:(NSFetchRequest *)persistentStoreRequest withContext:context error:error];
	}
	
	if (requestType == NSSaveRequestType)
	if ([persistentStoreRequest isKindOfClass:[NSSaveChangesRequest class]]) {
		return [self executePersistentStoreSaveChangesRequest:(NSSaveChangesRequest *)persistentStoreRequest withContext:context error:error];
	}
	
	if (error) {
		*error = AFIncrementalStoreError(0, [NSString stringWithFormat:NSLocalizedString(@"Unsupported NSFetchRequestResultType, %d", nil), persistentStoreRequest.requestType]);
	}
	
	return nil;
	
}

- (void) managedObjectContextDidRegisterObjectsWithIDs:(NSArray *)objectIDs {

	[super managedObjectContextDidRegisterObjectsWithIDs:objectIDs];
	
	for (NSManagedObjectID *objectID in objectIDs) {
		
		AFIncrementalStoreReferenceObject *referenceObject = [self referenceObjectForObjectID:objectID];
		NSCParameterAssert([referenceObject isKindOfClass:[AFIncrementalStoreReferenceObject class]]);
		
		[_registeredObjectIDsByResourceIdentifier setObject:objectID forKey:referenceObject];
		
	}

}

- (void) managedObjectContextDidUnregisterObjectsWithIDs:(NSArray *)objectIDs {

	[super managedObjectContextDidUnregisterObjectsWithIDs:objectIDs];
		
	for (NSManagedObjectID *objectID in objectIDs) {
		
		[_registeredObjectIDsByResourceIdentifier removeObjectsForKeys:[_registeredObjectIDsByResourceIdentifier allKeysForObject:objectID]];
		
	}

}

@end
