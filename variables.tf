variable "location"{
    type = string 
}

variable "zones" {
    type = list(string)
}
variable "resource_prefix" {
    type = map(string)
}

variable "envi" {
    type = string 
}