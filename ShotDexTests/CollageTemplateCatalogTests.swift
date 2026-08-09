import CoreGraphics
import Foundation
import Testing
@testable import ShotDex

struct CollageTemplateCatalogTests {
    /// The Create menu enables Collage for 2–9 photos; every count must have
    /// something to offer or the screen opens onto an empty template strip.
    @Test func everyCountHasTemplates() {
        for count in 2...9 {
            let templates = CollageTemplateCatalog.templates(for: count)
            #expect(!templates.isEmpty, "no templates for \(count) photos")
            for template in templates {
                #expect(template.cellCount == count)
                #expect(template.cells.count == count)
            }
        }
    }

    @Test func templateIDsAreUnique() {
        let ids = CollageTemplateCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func templateLookupFindsEveryCatalogEntry() {
        for template in CollageTemplateCatalog.all {
            #expect(CollageTemplateCatalog.template(id: template.id) == template)
        }
        #expect(CollageTemplateCatalog.template(id: "no-such-template") == nil)
    }

    /// Cells must tile the unit square exactly: no gaps (total area 1), no
    /// overlaps (pairwise intersection area 0), nothing outside [0,1]².
    /// The gutter math in `CollageGeometry` assumes exactly this.
    @Test func templateCellsTileUnitSpace() {
        let epsilon = 1e-6
        for template in CollageTemplateCatalog.all {
            var totalArea = 0.0
            for cell in template.cells {
                #expect(cell.x >= -epsilon && cell.y >= -epsilon, "\(template.id)")
                #expect(cell.x + cell.width <= 1 + epsilon, "\(template.id)")
                #expect(cell.y + cell.height <= 1 + epsilon, "\(template.id)")
                #expect(cell.width > epsilon && cell.height > epsilon, "\(template.id)")
                totalArea += cell.width * cell.height
            }
            #expect(abs(totalArea - 1) < 1e-4, "template \(template.id) area \(totalArea)")

            for i in 0..<template.cells.count {
                for j in (i + 1)..<template.cells.count {
                    let a = template.cells[i].cgRect
                    let b = template.cells[j].cgRect
                    let overlap = a.intersection(b)
                    let overlapArea = overlap.isNull ? 0 : overlap.width * overlap.height
                    #expect(
                        overlapArea < 1e-4,
                        "template \(template.id) cells \(i)/\(j) overlap"
                    )
                }
            }
        }
    }
}
