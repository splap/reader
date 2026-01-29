import Foundation
import ReaderCore
import UIKit

public enum SampleChapter {
    public static func make() -> Chapter {
        let title = "The Reader"
        let body = """
        Reading is the slow art of focus. A page is a promise that the world can be held still long enough to make sense.

        The first trick is letting the words settle. The second is letting them go.

        A good reader notices the white space. A great reader notices the silence between sentences.
        """

        let quote = "\n\n\"We read to know we are not alone.\" — C.S. Lewis\n\n"

        let appendix = """
        Notes
        1. A paragraph is a breath.
        2. A page is a room.
        3. A chapter is a walk.
        """

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 12

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 28),
            .paragraphStyle: paragraphStyle,
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .paragraphStyle: paragraphStyle,
        ]
        let italicAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 16),
            .paragraphStyle: paragraphStyle,
        ]
        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20),
            .paragraphStyle: paragraphStyle,
        ]

        let attributed = NSMutableAttributedString(string: title + "\n\n", attributes: titleAttributes)
        attributed.append(NSAttributedString(string: body, attributes: bodyAttributes))
        attributed.append(NSAttributedString(string: quote, attributes: italicAttributes))
        attributed.append(NSAttributedString(string: "Appendix\n", attributes: headingAttributes))
        attributed.append(NSAttributedString(string: appendix, attributes: bodyAttributes))

        return Chapter(id: "sample", attributedText: attributed, title: title)
    }
}
