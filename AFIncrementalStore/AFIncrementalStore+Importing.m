//  AFIncrementalStore+Importing.m

#import "AFIncrementalStore+BackingStore.h"
#import "AFIncrementalStore+Importing.h"
#import "AFIncrementalStore+ObjectIDs.h"

@implementation AFIncrementalStore (Importing)

- (NSManagedObject *) insertOrUpdateObjectWithEntity:(NSEntityDescription *)entity attributes:(NSDictionary *)attributes resourceIdentifier:(NSString *)resourceIdentifier inContext:(NSManagedObjectContext *)context {

	__block NSManagedObject *blockObject;
	
	[context performBlockAndWait:^{

		NSManagedObjectID *objectID;
		NSPersistentStoreCoordinator *psc = context.persistentStoreCoordinator;
		
		if (psc == self.persistentStoreCoordinator) {
		
			objectID = [self objectIDForEntity:entity withResourceIdentifier:resourceIdentifier];
		
		} else if (psc == self.backingPersistentStoreCoordinator) {
		
			objectID = [self objectIDForBackingObjectForEntity:entity withResourceIdentifier:resourceIdentifier];
		
		}
		
		NSCParameterAssert(!objectID || [objectID URIRepresentation]);
		
		if (objectID) {
			
			NSError *error = nil;
			if (!(blockObject = [context existingObjectWithID:objectID error:&error])) {
				NSCAssert2(NO, @"%s: Object ID exists, but object is not found: %@", __PRETTY_FUNCTION__, error);
			}
			
		}
		
		if (!blockObject) {
			
			//	Find the corresponding entity because in some cases the object needs to be instantiated as a backing entity instance with the same entity name.
		
			NSManagedObjectModel *model = psc.managedObjectModel;
			NSDictionary *allEntities = model.entitiesByName;
			NSEntityDescription *instantiatedEntity = [allEntities objectForKey:entity.name];
			Class class = NSClassFromString([instantiatedEntity managedObjectClassName]);
			
			blockObject = [(NSManagedObject *)[class alloc] initWithEntity:instantiatedEntity insertIntoManagedObjectContext:context];
			NSCParameterAssert(blockObject);
		
		}

	#if 0
		
		//	Not sure if obtaining permament IDs is very important
		
		if (!object.objectID || [object.objectID isTemporaryID]) {
			NSError *error = nil;
			BOOL didObtainPermanentID = [object.managedObjectContext obtainPermanentIDsForObjects:@[ object ] error:&error];
			NSCAssert2(didObtainPermanentID, @"%s: Did not obtain permanent ID for object %@", __PRETTY_FUNCTION__, object);
		}
		
	#endif
		
		[blockObject setValuesForKeysWithDictionary:attributes];

	}];
	
	NSManagedObject *object = blockObject;
	blockObject = nil;
	
	NSCParameterAssert([[object objectID] URIRepresentation]);
	
	return object;
	
}

- (void) importRepresentation:(NSDictionary *)representation ofEntity:(NSEntityDescription *)entity withResponse:(NSHTTPURLResponse *)response context:(NSManagedObjectContext *)childContext asManagedObject:(NSManagedObject **)outManagedObject backingObject:(NSManagedObject **)outBackingObject {

	__weak AFHTTPClient<AFIncrementalStoreHTTPClient> *httpClient = self.HTTPClient;
	
	NSManagedObjectContext *backingContext = [self backingManagedObjectContext];

	NSString *resourceIdentifier = [httpClient resourceIdentifierForRepresentation:representation ofEntity:entity fromResponse:response];
	NSDictionary *attributes = [httpClient attributesForRepresentation:representation ofEntity:entity fromResponse:response];
	
	NSManagedObject *managedObject = [self insertOrUpdateObjectWithEntity:entity attributes:attributes resourceIdentifier:resourceIdentifier inContext:childContext];
	
	NSManagedObject *backingObject = [self insertOrUpdateObjectWithEntity:entity attributes:attributes resourceIdentifier:resourceIdentifier inContext:backingContext];		
	[backingObject setValue:resourceIdentifier forKey:AFIncrementalStoreResourceIdentifierAttributeName];
	
	NSCParameterAssert([managedObject isKindOfClass:NSClassFromString([entity managedObjectClassName])]);	
	NSCParameterAssert([backingObject isKindOfClass:NSClassFromString([entity managedObjectClassName])]);
	[managedObject willAccessValueForKey:nil];
	[backingObject willAccessValueForKey:nil];
	NSCParameterAssert(![managedObject isFault]);
	NSCParameterAssert(![backingObject isFault]);
	
	if (outManagedObject)
		*outManagedObject = managedObject;

	if (outBackingObject)
		*outBackingObject = backingObject;
	
	if (![backingObject objectID] || [[backingObject objectID] isTemporaryID]) {
		[childContext insertObject:managedObject];
	}
	
	NSDictionary *relationshipRepresentations = [httpClient representationsForRelationshipsFromRepresentation:representation ofEntity:entity fromResponse:response];
	
	for (NSString *relationshipName in relationshipRepresentations) {
	
		NSRelationshipDescription *relationship = [[entity relationshipsByName] valueForKey:relationshipName];
		
		id representation = [relationshipRepresentations objectForKey:relationship.name];
		if (representation && ![representation isKindOfClass:[NSNull class]]) {
		
			[self importRepresentation:representation fromResponse:response context:childContext forRelationship:relationship usingManagedObject:managedObject backingObject:backingObject];
			
		}
		
	}

}

- (void) importRepresentation:(id)representationOrRepresentations fromResponse:(NSHTTPURLResponse *)response context:(NSManagedObjectContext *)childContext forRelationship:(NSRelationshipDescription *)relationship usingManagedObject:(NSManagedObject *)rootManagedObject backingObject:(NSManagedObject *)rootBackingObject {

	NSCParameterAssert(representationOrRepresentations);
	NSCParameterAssert(response);
	NSCParameterAssert(childContext);
	NSCParameterAssert(relationship);
	NSCParameterAssert(rootManagedObject);
	NSCParameterAssert(rootBackingObject);

	NSEntityDescription *entity = relationship.destinationEntity;
	
	if ([relationship isToMany]) {
	
		NSArray *representations = (NSArray *)representationOrRepresentations;
		if (![representations isKindOfClass:[NSArray class]]) {
			@throw([NSException exceptionWithName:AFIncrementalStoreRelationshipCardinalityException reason:NSLocalizedString(@"Cardinality of provided resource representation conflicts with Core Data model.", nil) userInfo:nil]);
		}
		
		id mutableManagedRelationshipObjects = [relationship isOrdered] ? [NSMutableOrderedSet orderedSet] : [NSMutableSet set];
		id mutableBackingRelationshipObjects = [relationship isOrdered] ? [NSMutableOrderedSet orderedSet] : [NSMutableSet set];
		
		for (NSDictionary *representation in representations) {
		
			NSManagedObject *managedObject = nil;
			NSManagedObject *backingObject = nil;
			
			[self importRepresentation:representation ofEntity:entity withResponse:response context:childContext asManagedObject:&managedObject backingObject:&backingObject];
			
			[mutableManagedRelationshipObjects addObject:managedObject];
			[mutableBackingRelationshipObjects addObject:backingObject];
				
		}

		[rootManagedObject setValue:mutableManagedRelationshipObjects forKey:relationship.name];
		[rootBackingObject setValue:mutableBackingRelationshipObjects forKey:relationship.name];
	
	} else {
	
		NSDictionary *representation = (NSDictionary *)representationOrRepresentations;
		if (![representation isKindOfClass:[NSDictionary class]]) {
			@throw([NSException exceptionWithName:AFIncrementalStoreRelationshipCardinalityException reason:NSLocalizedString(@"Cardinality of provided resource representation conflicts with Core Data model.", nil) userInfo:nil]);
		}
		
		NSManagedObject *managedRelationshipObject = nil;
		NSManagedObject *backingRelationshipObject = nil;
		
		[self importRepresentation:representation ofEntity:entity withResponse:response context:childContext asManagedObject:&managedRelationshipObject backingObject:&backingRelationshipObject];
		
		[rootBackingObject setValue:backingRelationshipObject forKey:relationship.name];
		[rootManagedObject setValue:managedRelationshipObject forKey:relationship.name];
	
	}
	
}

- (NSArray *) representationsFromResponse:(NSHTTPURLResponse *)response {

	id repOrReps = [self.HTTPClient representationOrArrayOfRepresentationsFromResponseObject:response];
	
	if ([repOrReps isKindOfClass:[NSDictionary class]])
		return [NSArray arrayWithObject:repOrReps];
	
	if ([repOrReps isKindOfClass:[NSArray class]])
		return (NSArray *)repOrReps;
	
	return nil;

}

@end
