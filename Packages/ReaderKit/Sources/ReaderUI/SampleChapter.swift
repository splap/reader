import Foundation
import ReaderCore

public enum SampleChapter {
    public static func make() -> Chapter {
        let title = "The Reader"
        let html = """
        <h1>The Reader</h1>
        <p>Reading is the slow art of focus. A page is a promise that the world can be held still long enough to make sense.</p>
        <p>The first trick is letting the words settle. The second is letting them go.</p>
        <p>A good reader notices the white space. A great reader notices the silence between sentences.</p>
        <blockquote>"We read to know we are not alone." — C.S. Lewis</blockquote>
        <h2>Appendix</h2>
        <p><strong>Notes</strong></p>
        <ol>
            <li>A paragraph is a breath.</li>
            <li>A page is a room.</li>
            <li>A chapter is a walk.</li>
        </ol>
        """

        let section = HTMLSection(
            html: html,
            basePath: "",
            spineItemId: "chapter1"
        )

        return Chapter(id: "sample", htmlSections: [section], title: title)
    }
}
