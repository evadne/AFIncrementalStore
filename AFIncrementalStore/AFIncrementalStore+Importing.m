//  AFIncrementalStore+Importing.m

#import "AFIncrementalStore+BackingStore.h"
#import "AFIncrementalStore+Importing.h"
#import "AFIncrementalStore+ObjectIDs.h"

@implementation AFIncrementalStore (Importing)

- (NSManagedObject *) insertOrUpdateObjectWithEntity:(NSEntityDescription *)entity attributes:(NSDictionary *)attributes resourceIdentifier:(NSString *)resourceIdentifier inContext:(NSManagedObjectContext *)context {

	NSManagedObjectID *objectID;
	NSPersistentStoreCoordinator *psc = context.persistentStoreCoordinator;
	
	if (psc == self.persistentStoreCoordinator) {
	
		objectID = [self objectIDForEntity:entity withResourceIdentifier:resourceIdentifier];
	
	} else if (psc == self.backingPersistentStoreCoordinator) {
	
		objectID = [self objectIDForBackingObjectForEntity:entity withResourceIdentifier:resourceIdentifier];
	
	}
	
	NSManagedObject *object = nil;
	
	if (objectID) {
	
		NSError *error = nil;
		if (!(object = [context existingObjectWithID:objectID error:&error])) {
			NSCAssert2(NO, @"%s: Object ID exists, but object is not found: %@", __PRETTY_FUNCTION__, error);
		}
	
	}
	
	if (!object) {
		
		//	Find the corresponding entity because in some cases the object needs
		//	to be instantiated as a backing entity instance with the same
		//	entity name.
	
		NSManagedObjectModel *model = psc.managedObjectModel;
		NSDictionary *allEntities = model.entitiesByName;
		NSEntityDescription *instantiatedEntity = [allEntities objectForKey:entity.name];
		Class class = NSClassFromString([instantiatedEntity managedObjectClassName]);
		
		object = [(NSManagedObject *)[class alloc] initWithEntity:instantiatedEntity insertIntoManagedObjectContext:context];
		NSCParameterAssert(object);
		
	}
	
	//	if (!object.objectID || [object.objectID isTemporaryID]) {
	//		NSError *error = nil;
	//		BOOL didObtainPermanentID = [object.managedObjectContext obtainPermanentIDsForObjects:@[ object ] error:&error];
	//		NSCAssert2(didObtainPermanentID, @"%s: Did not obtain permanent ID for object %@", __PRETTY_FUNCTION__, object);
	//	}
	
	[object setValuesForKeysWithDictionary:attributes];

	return object;

}

- (void) importRepresentation:(NSDictionary *)representation ofEntity:(NSEntityDescription *)entity withResponse:(NSHTTPURLResponse *)response context:(NSManagedObjectContext *)childContext asManagedObject:(NSManagedObject **)outManagedObject backingObject:(NSManagedObject **)outBackingObject {

	__weak AFHTTPClient<AFIncrementalStoreHTTPClient> *httpClient = self.HTTPClient;
	
	NSManagedObjectContext *backingContext = [self backingManagedObjectContext];

	NSManagedObject * (^insertedManagedObject)(NSEntityDescription *, NSString *, NSDictionary *) = ^ (NSEntityDescription *entity, NSString *resourceIdentifier, NSDictionary *attributes) {
	
		NSManagedObject *object = [self insertOrUpdateObjectWithEntity:entity attributes:attributes resourceIdentifier:resourceIdentifier inContext:childContext];

		return object;
		
	};

	NSManagedObject * (^insertedBackingObject)(NSEntityDescription *, NSString *, NSDictionary *) = ^ (NSEntityDescription *entity, NSString *resourceIdentifier, NSDictionary *attributes) {

		NSManagedObject *object = [self insertOrUpdateObjectWithEntity:entity attributes:attributes resourceIdentifier:resourceIdentifier inContext:backingContext];
		
		[object setValue:resourceIdentifier forKey:AFIncrementalStoreResourceIdentifierAttributeName];
		
		return object;

	};
	
	NSString *resourceIdentifier = [httpClient resourceIdentifierForRepresentation:representation ofEntity:entity fromResponse:response];
	NSDictionary *attributes = [httpClient attributesForRepresentation:representation ofEntity:entity fromResponse:response];
	
	NSManagedObject *managedObject = insertedManagedObject(entity, resourceIdentifier, attributes);
	NSManagedObject *backingObject = insertedBackingObject(entity, resourceIdentifier, attributes);
	
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
		NSEntityDescription *entity = relationship.destinationEntity;
		
		NSCParameterAssert(relationship);
		
		if ([relationship isToMany]) {
		
			NSArray *representations = (NSArray *)[relationshipRepresentations objectForKey:relationship.name];
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

			[managedObject setValue:mutableManagedRelationshipObjects forKey:relationship.name];
			[backingObject setValue:mutableBackingRelationshipObjects forKey:relationship.name];
		
		} else {
		
			NSDictionary *representation = (NSDictionary *)[relationshipRepresentations objectForKey:relationship.name];
			if (![representation isKindOfClass:[NSDictionary class]]) {
				@throw([NSException exceptionWithName:AFIncrementalStoreRelationshipCardinalityException reason:NSLocalizedString(@"Cardinality of provided resource representation conflicts with Core Data model.", nil) userInfo:nil]);
			}
			
			NSManagedObject *managedRelationshipObject = nil;
			NSManagedObject *backingRelationshipObject = nil;
			
			[self importRepresentation:representation ofEntity:entity withResponse:response context:childContext asManagedObject:&managedRelationshipObject backingObject:&backingRelationshipObject];
			
			[backingObject setValue:backingRelationshipObject forKey:relationship.name];
			[managedObject setValue:managedRelationshipObject forKey:relationship.name];
		
		}
	
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
