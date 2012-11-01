#import "NSManagedObject+AFIncrementalStore.h"
#import "AFIncrementalStore.h"

static char kAFResourceIdentifierObjectKey;

@implementation NSManagedObject (AFIncrementalStore)
@dynamic af_resourceIdentifier;

- (NSString *) af_resourceIdentifier {

    NSString *identifier = (NSString *)objc_getAssociatedObject(self, &kAFResourceIdentifierObjectKey);
    
    if (!identifier) {
        if ([self.objectID.persistentStore isKindOfClass:[AFIncrementalStore class]]) {
            id referenceObject = [(AFIncrementalStore *)self.objectID.persistentStore referenceObjectForObjectID:self.objectID];
            if ([referenceObject isKindOfClass:[NSString class]]) {
                return referenceObject;
            }
        }
    }
    
    return identifier;
    
}

- (void) af_setResourceIdentifier:(NSString *)resourceIdentifier {
  
		objc_setAssociatedObject(self, &kAFResourceIdentifierObjectKey, resourceIdentifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
		
}

- (BOOL) af_isPermanent {

	NSManagedObjectID *objectID = self.objectID;
	return objectID && ![objectID isTemporaryID];

}

- (void) af_setValue:(id)value forRelationship:(NSRelationshipDescription *)relationship {
	
	BOOL isToMany = [relationship isToMany];
	BOOL isOrdered = [relationship isOrdered];
	NSString *relationshipName = relationship.name;
	
	NSOrderedSet * (^orderedSet)(id) = ^ (id object) {
		
		if (!object)
			return (id)nil;
		
		if ([object isKindOfClass:[NSOrderedSet class]])
			return object;
		
		if ([object isKindOfClass:[NSSet class]]) {
			NSSet *set = (NSSet *)object;
			return [NSOrderedSet orderedSetWithSet:set];
		}
		
		if ([object isKindOfClass:[NSArray class]]) {
			NSArray *array = (NSArray *)object;
			return [NSOrderedSet orderedSetWithArray:array];
		}
			
		return [NSOrderedSet orderedSetWithObject:object];
	
	};
	
	NSSet * (^set)(id) = ^ (id object) {
	
		if (!object)
			return (id)nil;
		
		if ([object isKindOfClass:[NSSet class]])
			return object;
		
		if ([object isKindOfClass:[NSOrderedSet class]]) {
			NSOrderedSet *orderedSet = (NSOrderedSet *)object;
			return (id)[orderedSet set];
		}
		
		if ([object isKindOfClass:[NSArray class]]) {
			NSArray *array = (NSArray *)object;
			return [NSSet setWithArray:array];
		}
			
		return [NSSet setWithObject:object];
	
	};
	
	id (^singleObject)(id) = ^ (id object) {
	
		if (!object)
			return (id)nil;
		
		if ([object isKindOfClass:[NSArray class]]) {
			NSArray *array = (NSArray *)object;
			NSCParameterAssert([array count] <= 1);
			return [array lastObject];
		}
		
		if ([object isKindOfClass:[NSSet class]]) {
			NSSet *set = (NSSet *)object;
			NSCParameterAssert([set count] <= 1);
			return [[set allObjects] lastObject];
		}
		
		if ([object isKindOfClass:[NSOrderedSet class]]) {
			NSOrderedSet *orderedSet = (NSOrderedSet *)object;
			NSCParameterAssert([orderedSet count] <= 1);
			return [[orderedSet array] lastObject];
		}
		
		return object;
		
	};
	
	id outValue = isToMany ?
		(isOrdered ?
			orderedSet(value) :
			set(value)) :
		singleObject(value);
	
	[self setValue:outValue forKey:relationshipName];
	
}

@end
