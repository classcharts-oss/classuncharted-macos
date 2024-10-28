struct Student: Codable {
    public var id: Int
    public var name: String
    public var firstName: String
    public var lastName: String
    public var avatarUrl: String
    public var displayBehaviour: Bool
    public var displayDetentions: Bool
}

struct GetStudentInfoData: Codable {
    public var user: Student
}

struct GetStudentInfoMeta: Codable {
    public var version: String
}

typealias GetStudentInfo = ClientResponse<GetStudentInfoData, GetStudentInfoMeta>

